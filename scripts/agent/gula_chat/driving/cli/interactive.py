"""Interactive REPL handler — the main loop for chat.py interactive mode."""

from __future__ import annotations

import asyncio
import subprocess
from typing import List, Optional

from ...application.ports.driven.api_client_port import ApiClientPort
from ...application.ports.driven.clipboard_port import ClipboardPort
from ...application.ports.driven.config_port import ConfigPort
from ...application.services.auth_service import AuthService
from ...application.services.chat_service import ChatService
from ...application.services.subagent_service import SubagentService
from ...application.services.tool_orchestrator import ToolOrchestrator
from ...driven.context.project_context_builder import ProjectContextBuilder
from ...driven.images.image_detector import ImageDetector
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
from .commands import (
    SlashCommandRegistry,
    format_models_display,
    format_quota_display,
    format_subagents_display,
)
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
        auth_service: Authentication service for obtaining valid tokens.
        api_client: API client for backend calls (quota, models, etc.).
        subagent_service: Service for subagent listing and invocation.
        tool_orchestrator: Orchestrator for local tool execution.
        project_context_builder: Builder for project context metadata.
    """

    def __init__(
        self,
        chat_service: ChatService,
        config_port: ConfigPort,
        clipboard_port: ClipboardPort,
        auth_service: AuthService,
        api_client: ApiClientPort,
        subagent_service: SubagentService,
        tool_orchestrator: Optional[ToolOrchestrator] = None,
        project_context_builder: Optional[ProjectContextBuilder] = None,
    ) -> None:
        self._chat_service = chat_service
        self._config_port = config_port
        self._clipboard_port = clipboard_port
        self._auth_service = auth_service
        self._api_client = api_client
        self._subagent_service = subagent_service
        self._tool_orchestrator = tool_orchestrator
        self._context_builder = project_context_builder or ProjectContextBuilder()
        self._tool_display = ToolDisplay()
        self._image_detector = ImageDetector()
        self._console = get_console()

        # Session state
        self._conversation_id: Optional[int] = None
        self._total_cost: float = 0.0
        self._last_response: str = ""
        self._turn_count: int = 0
        self._project_name: str = _detect_project_name()
        self._is_first_message: bool = True

        # Sub-components
        self._input_handler = InputHandler()
        self._header = SessionHeader()
        self._commands = SlashCommandRegistry(
            config_port=config_port,
            clipboard_port=clipboard_port,
            auth_service=auth_service,
            api_client=api_client,
            subagent_service=subagent_service,
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
                    self._is_first_message = True
                    self._config_port.clear_project_conversation()
                    self._context_builder.rebuild()
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

                elif cmd_result.action == "fetch_quota":
                    await self._handle_fetch_quota()

                elif cmd_result.action == "list_models":
                    await self._handle_list_models()

                elif cmd_result.action == "list_subagents":
                    await self._handle_list_subagents()

                elif cmd_result.action == "invoke_subagent":
                    if cmd_result.action_data:
                        await self._handle_invoke_subagent(
                            cmd_result.action_data
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
        # Detect and encode images referenced in the prompt
        cleaned_prompt, image_attachments = self._image_detector.detect_images(prompt)
        images_payload = None
        if image_attachments:
            num = len(image_attachments)
            self._console.print(
                f"  [green]{num} imagen(es) detectada(s)[/green]"
            )
            images_payload = [
                {"data": img.data, "media_type": img.media_type}
                for img in image_attachments
            ]

        # Build project context: full on first message, minimal on continuations
        project_context = None
        if self._is_first_message:
            project_context = self._context_builder.build()
            self._is_first_message = False
        else:
            project_context = self._context_builder.build_minimal()

        current_prompt: Optional[str] = cleaned_prompt
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
                    project_context=project_context,
                    images=images_payload,
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

                # Loop: send tool results back, no new prompt, images, or context
                current_prompt = None
                current_tool_results = tool_results
                images_payload = None
                project_context = None
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

    async def _handle_fetch_quota(self) -> None:
        """Fetch and display quota information from the API."""
        try:
            config = await self._auth_service.ensure_valid_token()
            data = await self._api_client.get_quota(
                api_url=config.api_url,
                access_token=config.access_token,
            )
            output = format_quota_display(data, self._total_cost)
            self._console.print(output)
        except Exception as exc:
            self._console.print(f"  [red]Error al obtener quota: {exc}[/red]")
            self._console.print()

    async def _handle_list_models(self) -> None:
        """Fetch and display available models from the API."""
        try:
            config = await self._auth_service.ensure_valid_token()
            data = await self._api_client.get_models(
                api_url=config.api_url,
                access_token=config.access_token,
            )
            models = data if isinstance(data, list) else data.get("models", [])
            default_model = data.get("default_model", "") if isinstance(data, dict) else ""
            current = self._config_port.get_config().preferred_model or "auto"
            output = format_models_display(models, current, default_model)
            self._console.print(output)
        except Exception as exc:
            self._console.print(f"  [red]Error al obtener modelos: {exc}[/red]")
            self._console.print()

    async def _handle_list_subagents(self) -> None:
        """Fetch and display available subagents from the API."""
        try:
            subagents = await self._subagent_service.list_subagents()
            output = format_subagents_display(subagents)
            self._console.print(output)
        except Exception as exc:
            self._console.print(
                f"  [red]Error al obtener subagentes: {exc}[/red]"
            )
            self._console.print()

    async def _handle_invoke_subagent(self, action_data: str) -> None:
        """Invoke a subagent and stream the response.

        Args:
            action_data: String in the format "subagent_id\\nprompt".
        """
        parts = action_data.split("\n", maxsplit=1)
        if len(parts) < 2:
            self._console.print("  [red]Datos de subagente invalidos.[/red]")
            return

        subagent_id = parts[0]
        prompt = parts[1]

        self._console.print()
        self._console.print(
            f"  [cyan][Subagente: {subagent_id}][/cyan]"
        )
        self._console.print()

        renderer = SSERenderer()
        text_chunks: List[str] = []

        try:
            async for event in self._subagent_service.invoke(
                subagent_id=subagent_id,
                prompt=prompt,
                conversation_id=self._conversation_id,
            ):
                if isinstance(event, StartedEvent) and event.conversation_id:
                    self._conversation_id = event.conversation_id
                    self._config_port.set_project_conversation(
                        event.conversation_id
                    )

                if isinstance(event, CompleteEvent):
                    if event.total_cost > 0:
                        self._total_cost = event.total_cost
                    elif event.session_cost > 0:
                        self._total_cost += event.session_cost
                    self._turn_count += 1

                if isinstance(event, TextEvent) and event.content:
                    text_chunks.append(event.content)

                renderer.render(event)

        except KeyboardInterrupt:
            renderer.finalize()
            self._console.print()
            self._console.print("  [dim]Subagente cancelado[/dim]")
            self._console.print()
            return
        finally:
            renderer.finalize()

        if text_chunks:
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
