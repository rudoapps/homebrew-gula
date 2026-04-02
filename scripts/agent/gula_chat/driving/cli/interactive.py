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
from ...application.services.skill_service import SkillService
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
from ..ui.selector import SelectOption, select_option, select_option_async
from ..ui.tool_display import ToolDisplay
from .commands import (
    SlashCommandRegistry,
    format_models_display,
    format_quota_display,
    format_skills_display,
    format_subagents_display,
)
from .input_handler import InputHandler
from ... import __version__ as gula_version


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
        skill_service: Optional[SkillService] = None,
        tool_orchestrator: Optional[ToolOrchestrator] = None,
        project_context_builder: Optional[ProjectContextBuilder] = None,
    ) -> None:
        self._chat_service = chat_service
        self._config_port = config_port
        self._clipboard_port = clipboard_port
        self._auth_service = auth_service
        self._api_client = api_client
        self._subagent_service = subagent_service
        self._skill_service = skill_service
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
        self._last_broadcast_id: Optional[int] = None
        self._last_complete_max_iterations: bool = False

        # Sub-components
        self._input_handler = InputHandler()
        self._header = SessionHeader()
        self._commands = SlashCommandRegistry(
            config_port=config_port,
            clipboard_port=clipboard_port,
            auth_service=auth_service,
            api_client=api_client,
            subagent_service=subagent_service,
            skill_service=skill_service,
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

        # Load skills (best-effort, concurrent with startup data)
        if self._skill_service:
            try:
                await self._skill_service.load_skills()
            except Exception:
                pass

        # Fetch startup data with server-down retry loop
        while True:
            api_data = await self._fetch_startup_data()

            if api_data.get("_server_down"):
                self._console.print()
                chosen = await select_option_async(
                    [
                        SelectOption(value="retry", label="Reintentar conexion"),
                        SelectOption(value="exit", label="Salir"),
                    ],
                    title=f"\u26a0  {api_data.get('_error', 'El servidor no esta disponible')}",
                )
                if chosen == "retry":
                    continue
                return 0

            break

        broadcast_messages = api_data.get("messages", [])
        self._track_broadcast_ids(broadcast_messages)
        version_check = api_data.get("version_check")

        # Block if server requires a newer version
        if version_check and version_check.get("update_required"):
            self._header.show_update_required(
                version_check.get("message", ""),
            )
            return 1

        # Check RAG status for current project (best-effort)
        rag_info = await self._fetch_rag_info()

        # Detect auto-applied skill for this project type
        active_skill_name = None
        if self._skill_service:
            context = self._context_builder.build()
            project_type = context.get("project_type", "")
            auto_skill = self._skill_service.get_auto_skill_for_project(project_type)
            if auto_skill:
                active_skill_name = f"{auto_skill.icon} {auto_skill.display_name}".strip()

        # Show session header
        self._header.show(
            project_name=self._project_name,
            conversation_id=self._conversation_id,
            broadcast_messages=broadcast_messages,
            rag_info=rag_info,
            active_skill=active_skill_name,
        )

        # Offer architecture analysis if project is registered but has no guide
        if (rag_info and rag_info.get("project_id")
                and not rag_info.get("has_architecture_guide")):
            await self._offer_architecture_analysis(rag_info)

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

                elif cmd_result.action == "change_model":
                    if cmd_result.action_data:
                        await self._handle_change_model(cmd_result.action_data)

                elif cmd_result.action == "list_subagents":
                    await self._handle_list_subagents()

                elif cmd_result.action == "invoke_subagent":
                    if cmd_result.action_data:
                        await self._handle_invoke_subagent(
                            cmd_result.action_data
                        )

                elif cmd_result.action == "invoke_skill":
                    if cmd_result.action_data:
                        await self._handle_invoke_skill(
                            cmd_result.action_data
                        )

                elif cmd_result.action == "list_skills":
                    self._handle_list_skills()

                elif cmd_result.action == "show_mode":
                    if self._tool_orchestrator:
                        mode = self._tool_orchestrator.permission_mode.value
                        self._console.print(f"  Modo actual: [bold]{mode}[/bold]")
                        self._console.print("  [dim]Usa /mode <auto|ask|plan> para cambiar[/dim]")

                elif cmd_result.action == "change_mode":
                    if self._tool_orchestrator and cmd_result.action_data:
                        from ...domain.entities.permission_mode import PermissionMode
                        mode = PermissionMode(cmd_result.action_data)
                        self._tool_orchestrator.set_permission_mode(mode)
                        icons = {"auto": "\u26a1", "ask": "\U0001f512", "plan": "\U0001f4cb"}
                        icon = icons.get(mode.value, "")
                        self._console.print(f"  {icon} Modo: [bold]{mode.value}[/bold]")

                elif cmd_result.action == "show_changes":
                    if self._tool_orchestrator:
                        changes = self._tool_orchestrator.file_changes
                        if not changes:
                            self._console.print("  [dim]No hay cambios en esta sesion.[/dim]")
                        else:
                            self._console.print()
                            self._console.print(f"  [bold]{len(changes)} archivos modificados:[/bold]")
                            icons = {"write": "\u2795", "edit": "\u270f\ufe0f ", "move": "\u27a1\ufe0f "}
                            for c in changes:
                                icon = icons.get(c["action"], "\u2022")
                                self._console.print(f"  {icon} [dim]{c['action']}[/dim] {c['path']}")
                            self._console.print()

                elif cmd_result.action == "commit_auto":
                    await self._handle_commit()

                elif cmd_result.action == "commit_with_message":
                    if cmd_result.action_data:
                        await self._handle_commit(cmd_result.action_data)

                elif cmd_result.action == "review_changes":
                    await self._handle_review()

                elif cmd_result.action == "show_context":
                    await self._handle_context()

                elif cmd_result.action == "analyze_architecture":
                    await self._run_architecture_analysis()

                continue

            # Regular message — send to agent
            await self._send_message(user_input)

            # Check for new broadcast messages between turns
            await self._check_broadcasts()

    async def _send_message(
        self,
        prompt: str,
        system_prompt_addition: Optional[str] = None,
    ) -> None:
        """Send a message and handle the full tool execution loop.

        The loop continues sending tool_results back to the server until
        a CompleteEvent or ErrorEvent is received (no more tool requests).

        Args:
            prompt: The user's message (with @file refs already expanded).
            system_prompt_addition: Extra instructions for the system prompt (from skills).
        """
        # Reset per-turn auto-approval
        self._tool_display.reset_turn_approval()

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

        # Build full project context on every new prompt (matches bash behavior)
        project_context = self._context_builder.build()

        # Inject persistent memory on first message of session
        if self._is_first_message:
            try:
                from ...driven.memory.local_memory import LocalMemory
                memory_content = LocalMemory().get_all_memories()
                if memory_content:
                    if not system_prompt_addition:
                        system_prompt_addition = ""
                    system_prompt_addition += f"\n\n# Memoria del usuario (preferencias guardadas)\n{memory_content}"
            except Exception:
                pass

        self._is_first_message = False

        # Extract git_remote_url for RAG (top-level field, like bash client)
        git_remote_url = self._context_builder.get_git_remote_url()

        current_prompt: Optional[str] = cleaned_prompt
        current_tool_results = None

        while True:
            renderer = SSERenderer()
            # Show spinner immediately while waiting for server response
            if current_tool_results is not None:
                renderer.show_waiting_spinner("Procesando resultados...")
            else:
                renderer.show_waiting_spinner("Enviando...")
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
                    git_remote_url=git_remote_url,
                    gula_version=gula_version,
                    system_prompt_addition=system_prompt_addition,
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
                        self._last_complete_max_iterations = event.max_iterations_reached

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
            except Exception as exc:
                renderer.finalize()
                error_msg = str(exc)
                if any(s in error_msg for s in ["502", "503", "504", "conectar", "timeout", "timed out"]):
                    self._console.print()
                    self._console.print("  [yellow]\u26a0 El servidor no esta disponible. Intenta de nuevo en unos segundos.[/yellow]")
                else:
                    self._console.print()
                    self._console.print(f"  [red]Error: {error_msg}[/red]")
                self._console.print()
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
                git_remote_url = None
                system_prompt_addition = None
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

        # If max iterations was reached, offer to continue
        if self._last_complete_max_iterations:
            self._last_complete_max_iterations = False
            self._console.print()
            chosen = await select_option_async(
                [
                    SelectOption(value="continue", label="Continuar", description="Seguir con mas iteraciones"),
                    SelectOption(value="stop", label="Parar", description="Volver al prompt"),
                ],
                title="Se ha alcanzado el limite de iteraciones",
            )
            if chosen == "continue":
                await self._send_message("Continua con lo que estabas haciendo")
                return

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
        """Fetch models and show interactive selector."""
        try:
            models = await self._fetch_models()
            if models is None:
                return
            await self._show_model_selector(models)
        except Exception as exc:
            self._console.print(f"  [red]Error al obtener modelos: {exc}[/red]")

    async def _handle_change_model(self, model_id: str) -> None:
        """Validate model against backend and switch if valid."""
        try:
            models = await self._fetch_models()
            if models is None:
                return
            match = next((m for m in models if m.get("id") == model_id), None)
            if not match:
                available = ", ".join(m.get("id", "") for m in models if m.get("available", True))
                self._console.print(f"  [red]Modelo '{model_id}' no encontrado.[/red]")
                self._console.print(f"  [dim]Disponibles: {available}[/dim]")
                return
            if not match.get("available", True):
                self._console.print(f"  [yellow]Modelo '{model_id}' no disponible: {match.get('status_message', '')}[/yellow]")
                return
            self._apply_model(model_id, match)
        except Exception as exc:
            self._config_port.set_config("preferred_model", model_id)
            self._console.print(f"  [success]\u2713[/success] Modelo cambiado a: [bold]{model_id}[/bold]")
            self._console.print(f"  [dim](sin validar: {exc})[/dim]")

    async def _fetch_models(self) -> Optional[List[dict]]:
        """Fetch models from the API. Returns None on error."""
        try:
            config = await self._auth_service.ensure_valid_token()
            data = await self._api_client.get_models(
                api_url=config.api_url,
                access_token=config.access_token,
            )
            return data if isinstance(data, list) else data.get("models", [])
        except Exception as exc:
            self._console.print(f"  [red]Error al obtener modelos: {exc}[/red]")
            return None

    async def _show_model_selector(self, models: List[dict]) -> None:
        """Show interactive model selector."""
        current = self._config_port.get_config().preferred_model or "auto"

        options = [
            SelectOption(
                value="auto",
                label="auto",
                description="Routing automatico del servidor",
                active=current == "auto" or current == "",
            ),
        ]
        for m in models:
            mid = m.get("id", "")
            name = m.get("name", mid)
            provider = m.get("provider", "")
            inp = m.get("input_price", "?")
            out = m.get("output_price", "?")
            available = m.get("available", True)
            status = m.get("status", "")
            is_default = m.get("is_default", False)

            right = f"${inp}/1M in  ${out}/1M out"
            if is_default:
                right += "  (default)"

            desc = f"{name} ({provider})"
            if status == "no_credits":
                desc += " - sin creditos"
            elif status == "error":
                desc += " - error"

            options.append(SelectOption(
                value=mid,
                label=mid,
                description=desc,
                right_label=right,
                disabled=not available,
                active=current == mid,
            ))

        self._console.print()
        chosen = await select_option_async(options, title="Selecciona modelo")

        if chosen is None:
            self._console.print("  [dim]Cancelado[/dim]")
            return

        if chosen == "auto":
            self._config_port.set_config("preferred_model", "auto")
            self._console.print(
                "  [success]\u2713[/success] Modelo: [bold]auto[/bold] [dim](routing automatico)[/dim]"
            )
        else:
            match = next((m for m in models if m.get("id") == chosen), {})
            self._apply_model(chosen, match)

    def _apply_model(self, model_id: str, model_info: dict) -> None:
        """Save model selection and show confirmation."""
        self._config_port.set_config("preferred_model", model_id)
        name = model_info.get("name", model_id)
        inp = model_info.get("input_price", "?")
        out = model_info.get("output_price", "?")
        self._console.print(
            f"  [success]\u2713[/success] Modelo: [bold]{name}[/bold] "
            f"[dim](${inp}/1M in, ${out}/1M out)[/dim]"
        )

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

    async def _handle_invoke_skill(self, action_data: str) -> None:
        """Invoke a skill by name, expanding its template and sending as a message.

        Args:
            action_data: String in the format "skill_name\\nargs".
        """
        parts = action_data.split("\n", maxsplit=1)
        name = parts[0]
        args = parts[1] if len(parts) > 1 else ""

        if not self._skill_service:
            self._console.print("  [red]Skills no disponibles.[/red]")
            return

        resolution = self._skill_service.resolve(name, args)
        if not resolution:
            self._console.print(f"  [red]Skill '{name}' no encontrada.[/red]")
            return

        skill = self._skill_service.get_skill(name)
        if skill:
            icon = f"{skill.icon} " if skill.icon else ""
            self._console.print(
                f"  [cyan]{icon}{skill.display_name}[/cyan]"
            )
            self._console.print()

        # Send the expanded prompt as a regular message
        await self._send_message(
            resolution.expanded_prompt,
            system_prompt_addition=resolution.system_prompt_addition,
        )

    def _handle_list_skills(self) -> None:
        """Display available skills."""
        if not self._skill_service:
            self._console.print("  [red]Skills no disponibles.[/red]")
            return
        skills = self._skill_service.list_skills()
        output = format_skills_display(skills)
        self._console.print(output)

    async def _check_broadcasts(self) -> None:
        """Check for new broadcast messages between turns. Silent on failure."""
        try:
            config = await self._auth_service.ensure_valid_token()
            data = await self._api_client.get_messages(
                api_url=config.api_url,
                access_token=config.access_token,
                gula_version=gula_version,
                after_id=self._last_broadcast_id,
            )

            # Version check — block if update required
            version_check = data.get("version_check")
            if version_check and version_check.get("update_required"):
                self._header.show_update_required(
                    version_check.get("message", ""),
                )
                raise SystemExit(1)

            # Show only new broadcast messages
            messages = data.get("messages", [])
            if messages:
                self._track_broadcast_ids(messages)
                self._header._render_broadcasts(messages)
                self._console.print()
        except SystemExit:
            raise
        except Exception:
            pass

    def _track_broadcast_ids(self, messages: List[dict]) -> None:
        """Update _last_broadcast_id with the highest id from messages."""
        for msg in messages:
            msg_id = msg.get("id")
            if msg_id is not None:
                if self._last_broadcast_id is None or msg_id > self._last_broadcast_id:
                    self._last_broadcast_id = msg_id

    async def _handle_commit(self, message: Optional[str] = None) -> None:
        """Commit changes with auto-generated or manual message."""
        import subprocess

        # Get diff
        diff_result = subprocess.run(
            ["git", "diff", "--stat"],
            capture_output=True, text=True,
            cwd=self._context_builder._root,
        )
        staged_result = subprocess.run(
            ["git", "diff", "--cached", "--stat"],
            capture_output=True, text=True,
            cwd=self._context_builder._root,
        )

        diff_stat = diff_result.stdout.strip() + staged_result.stdout.strip()
        if not diff_stat:
            self._console.print("  [dim]No hay cambios para commitear.[/dim]")
            return

        if not message:
            # Auto-generate message using the LLM
            diff_detail = subprocess.run(
                ["git", "diff", "--no-color"],
                capture_output=True, text=True,
                cwd=self._context_builder._root,
            ).stdout[:3000]

            await self._send_message(
                f"Genera un mensaje de commit conciso (1-2 líneas, en inglés) para estos cambios. "
                f"Solo responde con el mensaje, nada más.\n\n```\n{diff_stat}\n\n{diff_detail}\n```"
            )
            return

        # Stage all and commit with provided message
        subprocess.run(
            ["git", "add", "-A"],
            cwd=self._context_builder._root,
        )
        result = subprocess.run(
            ["git", "commit", "-m", message],
            capture_output=True, text=True,
            cwd=self._context_builder._root,
        )
        if result.returncode == 0:
            self._console.print(f"  [success]\u2713[/success] {result.stdout.strip()}")
        else:
            self._console.print(f"  [red]{result.stderr.strip()}[/red]")

    async def _handle_review(self) -> None:
        """Review current git changes with AI."""
        import subprocess

        diff = subprocess.run(
            ["git", "diff", "--no-color"],
            capture_output=True, text=True,
            cwd=self._context_builder._root,
        ).stdout

        staged = subprocess.run(
            ["git", "diff", "--cached", "--no-color"],
            capture_output=True, text=True,
            cwd=self._context_builder._root,
        ).stdout

        combined = (diff + staged).strip()
        if not combined:
            self._console.print("  [dim]No hay cambios para revisar.[/dim]")
            return

        if len(combined) > 5000:
            combined = combined[:5000] + "\n... [truncado]"

        await self._send_message(
            f"Revisa estos cambios de código. Da feedback conciso sobre:\n"
            f"- Posibles bugs o errores\n"
            f"- Mejoras de calidad/legibilidad\n"
            f"- Problemas de seguridad\n"
            f"- Si respeta la arquitectura del proyecto\n\n"
            f"```diff\n{combined}\n```"
        )

    async def _handle_context(self) -> None:
        """Show token context diagnostics."""
        context = self._context_builder.build()
        file_tree_size = len(context.get("file_tree", ""))
        deps_size = len(context.get("dependencies", ""))
        rules_size = len(context.get("project_rules", ""))

        # Estimate token counts (rough: 1 token ≈ 4 chars)
        def est(chars: int) -> str:
            tokens = chars // 4
            if tokens > 1000:
                return f"~{tokens // 1000}K tokens"
            return f"~{tokens} tokens"

        lines = [
            "",
            "  [bold]Diagnostico de contexto[/bold]",
            "",
            f"  Conversacion:     #{self._conversation_id or 'nueva'}",
            f"  Turnos:           {self._turn_count}",
            f"  Coste acumulado:  ${self._total_cost:.4f}",
            "",
            "  [bold]Contexto enviado por turno:[/bold]",
            f"  System prompt:    ~10K tokens (base)",
            f"  File tree:        {est(file_tree_size)} ({file_tree_size} chars)",
            f"  Dependencias:     {est(deps_size)} ({deps_size} chars)",
            f"  Project rules:    {est(rules_size)} ({rules_size} chars)",
        ]

        # Check if architecture guide and skills are active
        rag_info = await self._fetch_rag_info()
        if rag_info and rag_info.get("has_architecture_guide"):
            lines.append(f"  Guia arquitectura: ~1.5K tokens (del proyecto)")

        if self._skill_service:
            ctx = context.get("project_type", "")
            auto_skill = self._skill_service.get_auto_skill_for_project(ctx)
            if auto_skill:
                skill_size = len(auto_skill.system_prompt_addition or "")
                lines.append(f"  Skill activa:     {est(skill_size)} ({auto_skill.display_name})")

        # Memory
        try:
            from ...driven.memory.local_memory import LocalMemory
            mem = LocalMemory().get_all_memories()
            if mem:
                lines.append(f"  Memoria usuario:  {est(len(mem))}")
        except Exception:
            pass

        lines.append("")
        self._console.print("\n".join(lines))

    async def _fetch_startup_data(self) -> dict:
        """Fetch broadcast messages and version check.

        If not authenticated, triggers interactive browser login first.
        Returns {} on failure, or {"_server_down": True} if server is unavailable.
        """
        import httpx
        from ...application.services.auth_service import AuthenticationError, ServerUnavailableError

        try:
            config = await self._auth_service.ensure_valid_token()
        except ServerUnavailableError as exc:
            return {"_server_down": True, "_error": str(exc)}
        except AuthenticationError:
            # No valid tokens — trigger browser-based login
            try:
                config = await self._do_interactive_login()
            except Exception:
                config = None
            if config is None:
                return {}

        try:
            return await self._api_client.get_messages(
                api_url=config.api_url,
                access_token=config.access_token,
                gula_version=gula_version,
            )
        except (httpx.ConnectError, httpx.ConnectTimeout, httpx.ReadTimeout) as exc:
            return {"_server_down": True, "_error": "No se puede conectar al servidor. Verifica tu conexion."}
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code in (502, 503, 504):
                return {"_server_down": True, "_error": f"El servidor no esta disponible ({exc.response.status_code})."}
            return {}
        except Exception:
            return {}

    async def _fetch_rag_info(self) -> Optional[dict]:
        """Fetch RAG project info if current directory is a git repo."""
        git_url = self._context_builder.get_git_remote_url()
        if not git_url:
            return None
        try:
            config = await self._auth_service.ensure_valid_token()
            return await self._api_client.check_rag(
                api_url=config.api_url,
                access_token=config.access_token,
                git_remote_url=git_url,
            )
        except Exception:
            return None

    async def _offer_architecture_analysis(self, rag_info: dict) -> None:
        """Ask the user if they want to analyze project architecture."""
        project_name = rag_info.get("project_name", self._project_name)

        chosen = await select_option_async(
            [
                SelectOption(value="yes", label="Si, analizar arquitectura", description=f"Analiza {project_name} y genera una guia para mejorar las respuestas"),
                SelectOption(value="no", label="No, continuar", description="Puedes hacerlo mas tarde con /analyze"),
            ],
            title="Este proyecto no tiene guia de arquitectura. Quieres generarla?",
        )

        if chosen == "yes":
            await self._run_architecture_analysis(rag_info)

    async def _run_architecture_analysis(self, rag_info: Optional[dict] = None) -> None:
        """Send project files to backend for architecture analysis."""
        if not rag_info:
            rag_info = await self._fetch_rag_info()
        if not rag_info or not rag_info.get("project_id"):
            self._console.print("  [red]Proyecto no encontrado en el RAG.[/red]")
            return

        project_id = rag_info["project_id"]

        from ..ui.spinner import Spinner
        spinner = Spinner()
        spinner.start("Analizando arquitectura del proyecto...")

        # Build payload from local project
        context = self._context_builder.build()
        key_files_content = {}
        root = self._context_builder._root

        # Include config/key files
        for kf in context.get("key_files", []):
            path = root / kf
            if path.is_file():
                try:
                    key_files_content[kf] = path.read_text(errors="replace")[:3000]
                except OSError:
                    pass

        # Collect all code files with their sizes, then pick the most
        # representative ones (largest files have the most patterns).
        # No hardcoded patterns — the LLM deduces the architecture.
        code_extensions = {".py", ".swift", ".kt", ".ts", ".js", ".dart", ".go", ".rs", ".java"}
        skip_dirs = {"node_modules", "__pycache__", ".git", "venv", ".venv", "build", "dist", "Pods",
                     "migrations", ".build", "DerivedData"}
        candidates = []
        for path in root.rglob("*"):
            if not path.is_file() or path.suffix not in code_extensions:
                continue
            rel = str(path.relative_to(root))
            if any(s in rel.split("/") for s in skip_dirs):
                continue
            try:
                size = path.stat().st_size
                if size < 100:
                    continue
                candidates.append((size, rel, path))
            except OSError:
                pass

        # Sort by size descending — largest files contain the real patterns
        candidates.sort(key=lambda x: x[0], reverse=True)

        # Pick top files ensuring diversity across directories
        seen_dirs: set = set()
        for _, rel, path in candidates:
            if len(key_files_content) >= 20:
                break
            parent = str(path.parent.relative_to(root))
            if parent in seen_dirs:
                continue
            try:
                key_files_content[rel] = path.read_text(errors="replace")[:4000]
                seen_dirs.add(parent)
            except OSError:
                pass

        spinner.update("Generando guia de arquitectura con IA...")

        try:
            config = await self._auth_service.ensure_valid_token()
            result = await self._api_client.analyze_architecture(
                api_url=config.api_url,
                access_token=config.access_token,
                project_id=project_id,
                payload={
                    "file_tree": context.get("file_tree", ""),
                    "dependencies": context.get("dependencies", ""),
                    "key_files": key_files_content,
                    "project_type": context.get("project_type", ""),
                },
            )
            if result.get("status") == "completed":
                spinner.stop(
                    f"Guia de arquitectura generada ({result.get('guide_length', 0)} chars)",
                    "success",
                )
            else:
                spinner.stop(f"Error: {result.get('message', 'unknown')}", "error")
        except Exception as exc:
            spinner.stop(f"Error al analizar: {exc}", "error")

    async def _do_interactive_login(self) -> Optional["AppConfig"]:
        """Run browser-based login flow with Rich UI feedback.

        Returns:
            AppConfig on success, None on failure.
        Raises:
            ServerUnavailableError: If the server is down.
        """
        import httpx
        from rich.panel import Panel
        from rich.text import Text
        from ...application.services.auth_service import AuthenticationError, ServerUnavailableError

        # Check if server is reachable before showing login UI
        try:
            config = self._auth_service.get_config()
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(f"{config.api_url}/agent/models")
                if resp.status_code in (502, 503, 504):
                    raise ServerUnavailableError(
                        f"El servidor no esta disponible ({resp.status_code})."
                    )
        except (httpx.ConnectError, httpx.ConnectTimeout, httpx.ReadTimeout):
            raise ServerUnavailableError(
                "No se puede conectar al servidor. Verifica tu conexion."
            )
        except ServerUnavailableError:
            raise

        self._console.print()

        # Show login prompt
        text = Text()
        text.append("\U0001f511 ", style="yellow")
        text.append("Inicio de sesion requerido", style="yellow bold")
        text.append("\n\n")
        text.append("Se abrira el navegador para iniciar sesion...", style="dim")
        panel = Panel(text, border_style="yellow", padding=(0, 1), expand=False)
        self._console.print(panel)
        self._console.print()

        try:
            with self._console.status(
                "  [dim]Esperando autenticacion en el navegador...[/dim]",
                spinner="dots",
            ):
                config = await self._auth_service.login()

            self._console.print(
                "  [green]\u2713[/green] Sesion iniciada correctamente"
            )
            self._console.print()
            return config

        except AuthenticationError as exc:
            self._console.print(f"  [red]\u2717 {exc}[/red]")
            self._console.print()
            return None
        except Exception as exc:
            self._console.print(f"  [red]\u2717 Error de autenticacion: {exc}[/red]")
            self._console.print()
            return None

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
