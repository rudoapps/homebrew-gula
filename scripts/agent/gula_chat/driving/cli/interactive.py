"""Interactive REPL handler — the main loop for chat.py interactive mode."""

from __future__ import annotations

import asyncio
import subprocess
from typing import List, Optional

from ...application.services.chat_service import ChatService
from ...application.ports.driven.config_port import ConfigPort
from ...application.ports.driven.clipboard_port import ClipboardPort
from ...domain.entities.sse_event import (
    StartedEvent,
    CompleteEvent,
    ToolRequestsEvent,
)
from ..ui.console import get_console
from ..ui.header import SessionHeader
from ..ui.renderer import SSERenderer
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
    handle tool_requests (Phase 3 stub) -> repeat.

    Args:
        chat_service: Service for sending messages and streaming responses.
        config_port: Configuration port for settings access.
        clipboard_port: Clipboard port for copy operations.
    """

    def __init__(
        self,
        chat_service: ChatService,
        config_port: ConfigPort,
        clipboard_port: ClipboardPort,
    ) -> None:
        self._chat_service = chat_service
        self._config_port = config_port
        self._clipboard_port = clipboard_port
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
        """Send a message to the agent and render the streamed response.

        Args:
            prompt: The user's message (with @file refs already expanded).
        """
        renderer = SSERenderer()
        self._last_response = ""
        text_chunks: List[str] = []

        try:
            async for event in self._chat_service.send_message(
                prompt=prompt,
                conversation_id=self._conversation_id,
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

                # Accumulate text for /copy
                from ...domain.entities.sse_event import TextEvent
                if isinstance(event, TextEvent) and event.content:
                    text_chunks.append(event.content)

                # Phase 3 stub: tool requests are displayed but not executed
                if isinstance(event, ToolRequestsEvent) and event.tool_calls:
                    renderer.render(event)
                    self._console.print()
                    self._console.print(
                        "  [warning]Ejecucion de herramientas no disponible "
                        "aun (Phase 3)[/warning]"
                    )
                    self._console.print()
                    continue

                renderer.render(event)

        except KeyboardInterrupt:
            renderer.finalize()
            self._console.print()
            self._console.print("  [dim]Mensaje cancelado[/dim]")
            self._console.print()
            return

        finally:
            renderer.finalize()

        self._last_response = "".join(text_chunks)
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
