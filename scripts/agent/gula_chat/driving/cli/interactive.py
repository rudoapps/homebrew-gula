"""Interactive REPL handler — the main loop for chat.py interactive mode."""

from __future__ import annotations

import asyncio
import subprocess
from typing import List, Optional

from ...application.services.chat_service import ChatService
from ...application.services.tool_orchestrator import ToolOrchestrator
from ...application.ports.driven.config_port import ConfigPort
from ...application.ports.driven.clipboard_port import ClipboardPort
from ...domain.entities.sse_event import (
    SSEEvent,
    StartedEvent,
    CompleteEvent,
    ErrorEvent,
    TextEvent,
    ToolRequestsEvent,
)
from ..ui.console import get_console
from ..ui.header import SessionHeader
from ..ui.renderer import SSERenderer
from ..ui.tool_display import ToolDisplay
from .commands import SlashCommandRegistry
from .input_handler import InputHandler


def _detect_project_name() -> str:
    """Detect the current project name from git or cwd."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            import os
            return os.path.basename(result.stdout.strip())
    except (subprocess.SubprocessError, OSError):
        pass

    import os
    return os.path.basename(os.getcwd())


class InteractiveHandler:
    """Handles the interactive REPL chat session.

    Manages the loop of: read input -> check slash commands ->
    expand @files -> send to chat_service -> render SSE events ->
    execute tool_requests -> send results back -> repeat until complete.

    Args:
        chat_service: Service for sending messages and streaming responses.
        config_port: Configuration port for settings access.
        clipboard_port: Clipboard port for copy operations.
        tool_orchestrator: Orchestrator for local tool execution.
    """

    def __init__(
        self,
        chat_service: ChatService,
        config_port: ConfigPort,
        clipboard_port: ClipboardPort,
        tool_orchestrator: Optional[ToolOrchestrator] = None,
    ) -> None:
        self._chat_service = chat_service
        self._config_port = config_port
        self._clipboard_port = clipboard_port
        self._tool_orchestrator = tool_orchestrator
        self._tool_display = ToolDisplay()
        self._console = get_console()

        # Session state
        self._conversation_id: Optional[int] = None
        self._total_cost: float = 0.0
        self._last_response: str = ""
        self._turn_count: int = 0
        self._project_name: str = _detect_project_name()

        # Sub-components
        self._input_handler = InputHandler()
        self._header = SessionHeader()
        self._commands = SlashCommandRegistry(
            config_port=config_port,
            clipboard_port=clipboard_port,
            get_last_response=lambda: self._last_response,
            get_total_cost=lambda: self._total_cost,
            get_conversation_id=lambda: self._conversation_id,
        )

    def run(self) -> int:
        """Run the interactive REPL loop.

        Returns:
            Exit code: 0 for normal exit.
        """
        try:
            return asyncio.run(self._loop())
        except KeyboardInterrupt:
            self._show_exit_summary()
            return 0

    async def _loop(self) -> int:
        """Main async REPL loop."""
        # Try to resume last conversation for this project
        self._conversation_id = self._config_port.get_project_conversation()

        # Show session header
        self._header.show(
            project_name=self._project_name,
            conversation_id=self._conversation_id,
        )

        while True:
            try:
                user_input = await self._input_handler.read_input()
            except KeyboardInterrupt:
                self._show_exit_summary()
                return 0

            # EOF (Ctrl+D) — exit
            if user_input is None:
                self._show_exit_summary()
                return 0

            # Empty input — skip
            if not user_input.strip():
                continue

            # Check for slash commands
            cmd_result = self._commands.dispatch(user_input)
            if cmd_result is not None:
                if cmd_result.output:
                    self._console.print(f"  {cmd_result.output}")
                    self._console.print()

                if not cmd_result.should_continue:
                    self._show_exit_summary()
                    return 0

                # Handle command actions
                if cmd_result.action == "new_conversation":
                    self._conversation_id = None
                    self._config_port.clear_project_conversation()
                    self._header.show_new_conversation()

                elif cmd_result.action == "resume_conversation":
                    if cmd_result.action_data:
                        self._conversation_id = int(cmd_result.action_data)
                        self._config_port.set_project_conversation(
                            self._conversation_id
                        )
                        self._header.show_resumed_conversation(
                            self._conversation_id
                        )

                continue

            # Regular message — send to agent
            await self._send_message(user_input)

    async def _send_message(self, prompt: str) -> None:
        """Send a message and handle the full tool execution loop.

        The loop continues sending tool_results back to the server until
        a CompleteEvent or ErrorEvent is received (no more tool requests).

        Args:
            prompt: The user's message (with @file refs already expanded).
        """
        current_prompt: Optional[str] = prompt
        current_tool_results = None

        while True:
            renderer = SSERenderer()
            text_chunks: List[str] = []
            pending_tool_event: Optional[ToolRequestsEvent] = None
            turn_complete = False

            try:
                async for event in self._chat_service.send_message(
                    prompt=current_prompt,
                    conversation_id=self._conversation_id,
                    tool_results=current_tool_results,
                ):
                    # Track conversation ID
                    if isinstance(event, StartedEvent) and event.conversation_id:
                        self._conversation_id = event.conversation_id
                        self._config_port.set_project_conversation(
                            event.conversation_id
                        )

                    # Track cost from complete events
                    if isinstance(event, CompleteEvent):
                        if event.total_cost > 0:
                            self._total_cost = event.total_cost
                        elif event.session_cost > 0:
                            self._total_cost += event.session_cost
                        self._turn_count += 1
                        turn_complete = True

                    # Accumulate text for /copy
                    if isinstance(event, TextEvent) and event.content:
                        text_chunks.append(event.content)

                    # Handle tool requests
                    if isinstance(event, ToolRequestsEvent) and event.tool_calls:
                        if event.conversation_id:
                            self._conversation_id = event.conversation_id
                        pending_tool_event = event
                        renderer.render(event)
                        continue

                    # Handle errors as terminal
                    if isinstance(event, ErrorEvent):
                        renderer.render(event)
                        turn_complete = True
                        continue

                    renderer.render(event)

            except KeyboardInterrupt:
                renderer.finalize()
                self._console.print()
                self._console.print("  [dim]Mensaje cancelado[/dim]")
                self._console.print()
                if self._tool_orchestrator:
                    self._tool_orchestrator.request_abort()
                return

            finally:
                renderer.finalize()

            # Accumulate text for /copy
            if text_chunks:
                self._last_response = "".join(text_chunks)

            # If we got a tool request event and have an orchestrator, execute tools
            if pending_tool_event and self._tool_orchestrator:
                self._console.print()

                try:
                    tool_results = await self._tool_orchestrator.execute_all(
                        pending_tool_event.tool_calls
                    )
                except KeyboardInterrupt:
                    self._console.print()
                    self._console.print("  [dim]Ejecucion de herramientas cancelada[/dim]")
                    self._console.print()
                    self._tool_orchestrator.request_abort()
                    return

                # Loop: send tool results back, no new prompt
                current_prompt = None
                current_tool_results = tool_results
                self._console.print()
                continue

            elif pending_tool_event and not self._tool_orchestrator:
                # No orchestrator — show Phase 3 stub message
                self._console.print()
                self._console.print(
                    "  [warning]Ejecucion de herramientas no disponible "
                    "(tool_orchestrator no configurado)[/warning]"
                )
                self._console.print()
                break

            # No more tool requests or turn is complete
            if turn_complete or not pending_tool_event:
                break

        self._console.print()

    def _show_exit_summary(self) -> None:
        """Display a session summary on exit."""
        self._console.print()
        parts = ["Sesion finalizada"]

        if self._turn_count > 0:
            parts.append(f"{self._turn_count} turnos")

        if self._total_cost > 0:
            parts.append(f"${self._total_cost:.4f}")

        if self._conversation_id is not None:
            parts.append(f"conversacion #{self._conversation_id}")

        summary = " \u00b7 ".join(parts)
        self._console.print(f"  [dim]{summary}[/dim]")
        self._console.print()
