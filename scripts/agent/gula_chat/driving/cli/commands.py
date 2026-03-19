"""Slash command registry for interactive mode."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Dict, List, Optional

from ...application.ports.driven.clipboard_port import ClipboardPort
from ...application.ports.driven.config_port import ConfigPort
from ..ui.console import get_console


@dataclass
class CommandResult:
    """Result of executing a slash command.

    Attributes:
        handled: Whether the command was recognized and handled.
        output: Optional output message to display.
        should_continue: Whether the REPL loop should continue.
            False means exit.
        action: Optional action identifier for the caller to handle
            (e.g. "new_conversation", "change_model").
        action_data: Optional data associated with the action.
    """

    handled: bool = True
    output: str = ""
    should_continue: bool = True
    action: Optional[str] = None
    action_data: Optional[str] = None


class SlashCommandRegistry:
    """Registry and dispatcher for slash commands in interactive mode.

    Each command is a method that receives the raw argument string and
    returns a CommandResult. The registry maps command names to methods
    and handles dispatch, including aliases.

    Args:
        config_port: Configuration port for reading/writing settings.
        clipboard_port: Clipboard port for copy operations.
        get_last_response: Callable that returns the last assistant response text.
        get_total_cost: Callable that returns the cumulative session cost.
        get_conversation_id: Callable that returns the current conversation ID.
    """

    def __init__(
        self,
        config_port: ConfigPort,
        clipboard_port: ClipboardPort,
        get_last_response: Callable[[], str],
        get_total_cost: Callable[[], float],
        get_conversation_id: Callable[[], Optional[int]],
    ) -> None:
        self._config_port = config_port
        self._clipboard_port = clipboard_port
        self._get_last_response = get_last_response
        self._get_total_cost = get_total_cost
        self._get_conversation_id = get_conversation_id
        self._console = get_console()

        # Command name -> handler method mapping
        self._commands: Dict[str, Callable[[str], CommandResult]] = {
            "exit": self._cmd_exit,
            "quit": self._cmd_exit,
            "q": self._cmd_exit,
            "new": self._cmd_new,
            "cost": self._cmd_cost,
            "copy": self._cmd_copy,
            "clear": self._cmd_clear,
            "help": self._cmd_help,
            "models": self._cmd_models,
            "model": self._cmd_model,
            "resume": self._cmd_resume,
            "preview": self._cmd_preview,
            "debug": self._cmd_debug,
            "undo": self._cmd_undo,
            "diff": self._cmd_diff,
            "quota": self._cmd_quota,
            "presupuesto": self._cmd_quota,
            # Subagent shortcuts — stubs for Phase 3
            "review": self._cmd_subagent_stub,
            "test": self._cmd_subagent_stub,
            "explain": self._cmd_subagent_stub,
            "refactor": self._cmd_subagent_stub,
            "document": self._cmd_subagent_stub,
            "subagents": self._cmd_subagent_stub,
            "subagent": self._cmd_subagent_stub,
        }

    def dispatch(self, input_text: str) -> Optional[CommandResult]:
        """Try to dispatch a slash command from the given input.

        Args:
            input_text: Raw user input (should start with /).

        Returns:
            A CommandResult if the input is a slash command, or None
            if it does not start with /.
        """
        stripped = input_text.strip()
        if not stripped.startswith("/"):
            return None

        parts = stripped[1:].split(maxsplit=1)
        if not parts:
            return None

        cmd_name = parts[0].lower()
        args = parts[1] if len(parts) > 1 else ""

        handler = self._commands.get(cmd_name)
        if handler is None:
            return CommandResult(
                handled=True,
                output=f"Comando desconocido: /{cmd_name}. Escribe /help para ver los comandos disponibles.",
            )

        return handler(args)

    # ── Command implementations ──────────────────────────────────────────

    def _cmd_exit(self, args: str) -> CommandResult:
        """Exit the interactive session."""
        return CommandResult(handled=True, should_continue=False)

    def _cmd_new(self, args: str) -> CommandResult:
        """Start a new conversation."""
        return CommandResult(
            handled=True,
            output="Nueva conversacion iniciada.",
            action="new_conversation",
        )

    def _cmd_cost(self, args: str) -> CommandResult:
        """Show accumulated cost for this session."""
        total = self._get_total_cost()
        conv_id = self._get_conversation_id()
        lines = [f"Coste de la sesion: ${total:.4f}"]
        if conv_id is not None:
            lines.append(f"Conversacion: #{conv_id}")
        return CommandResult(handled=True, output="\n".join(lines))

    def _cmd_copy(self, args: str) -> CommandResult:
        """Copy the last assistant response to the clipboard."""
        last = self._get_last_response()
        if not last:
            return CommandResult(
                handled=True,
                output="No hay respuesta para copiar.",
            )
        try:
            self._clipboard_port.copy_text(last)
            return CommandResult(
                handled=True,
                output="Respuesta copiada al portapapeles.",
            )
        except Exception as exc:
            return CommandResult(
                handled=True,
                output=f"Error al copiar: {exc}",
            )

    def _cmd_clear(self, args: str) -> CommandResult:
        """Clear the terminal screen."""
        self._console.clear()
        return CommandResult(handled=True)

    def _cmd_help(self, args: str) -> CommandResult:
        """Show available commands."""
        help_text = (
            "Comandos disponibles:\n"
            "  /new              Nueva conversacion\n"
            "  /cost             Mostrar coste acumulado\n"
            "  /copy             Copiar ultima respuesta al portapapeles\n"
            "  /clear            Limpiar la pantalla\n"
            "  /models           Listar modelos disponibles\n"
            "  /model <id>       Cambiar modelo\n"
            "  /resume <id>      Retomar conversacion por ID\n"
            "  /undo             Deshacer ultimo cambio (stub)\n"
            "  /diff             Mostrar cambios recientes (stub)\n"
            "  /preview          Alternar modo preview\n"
            "  /debug            Alternar modo debug\n"
            "  /quota            Mostrar uso del presupuesto\n"
            "  /presupuesto      Alias de /quota\n"
            "\n"
            "Subagentes (Phase 3):\n"
            "  /review           Revisar codigo\n"
            "  /test             Generar tests\n"
            "  /explain          Explicar codigo\n"
            "  /refactor         Refactorizar\n"
            "  /document         Documentar\n"
            "  /subagents        Listar subagentes\n"
            "  /subagent <id>    Enviar tarea a subagente\n"
            "\n"
            "  /exit /quit /q    Salir\n"
            "\n"
            "Atajos:\n"
            "  @archivo.py       Adjuntar contenido de un archivo\n"
            "  Esc+Enter         Nueva linea (sin enviar)\n"
            "  Ctrl+D            Salir\n"
            "  Ctrl+C            Cancelar mensaje actual"
        )
        return CommandResult(handled=True, output=help_text)

    def _cmd_models(self, args: str) -> CommandResult:
        """List available models."""
        config = self._config_port.get_config()
        current = config.preferred_model or "auto"
        return CommandResult(
            handled=True,
            output=f"Modelo actual: {current}\nUsa /model <id> para cambiar.",
            action="list_models",
        )

    def _cmd_model(self, args: str) -> CommandResult:
        """Change the active model."""
        model_id = args.strip()
        if not model_id:
            config = self._config_port.get_config()
            current = config.preferred_model or "auto"
            return CommandResult(
                handled=True,
                output=f"Modelo actual: {current}\nUsa: /model <id>",
            )
        self._config_port.set_config("preferred_model", model_id)
        return CommandResult(
            handled=True,
            output=f"Modelo cambiado a: {model_id}",
            action="change_model",
            action_data=model_id,
        )

    def _cmd_resume(self, args: str) -> CommandResult:
        """Resume an existing conversation by ID."""
        conv_str = args.strip()
        if not conv_str:
            return CommandResult(
                handled=True,
                output="Uso: /resume <conversation_id>",
            )
        try:
            conv_id = int(conv_str)
        except ValueError:
            return CommandResult(
                handled=True,
                output=f"ID de conversacion invalido: {conv_str}",
            )
        return CommandResult(
            handled=True,
            output=f"Retomando conversacion #{conv_id}",
            action="resume_conversation",
            action_data=str(conv_id),
        )

    def _cmd_preview(self, args: str) -> CommandResult:
        """Toggle preview mode."""
        config = self._config_port.get_config()
        new_val = not config.preview_mode
        self._config_port.set_config("preview_mode", new_val)
        state = "activado" if new_val else "desactivado"
        return CommandResult(
            handled=True,
            output=f"Modo preview {state}.",
        )

    def _cmd_debug(self, args: str) -> CommandResult:
        """Toggle debug mode."""
        config = self._config_port.get_config()
        new_val = not config.debug_mode
        self._config_port.set_config("debug_mode", new_val)
        state = "activado" if new_val else "desactivado"
        return CommandResult(
            handled=True,
            output=f"Modo debug {state}.",
        )

    def _cmd_undo(self, args: str) -> CommandResult:
        """Undo last change — stub for Phase 3."""
        return CommandResult(
            handled=True,
            output="Undo no disponible aun (Phase 3).",
        )

    def _cmd_diff(self, args: str) -> CommandResult:
        """Show recent changes — stub for Phase 3."""
        return CommandResult(
            handled=True,
            output="Diff no disponible aun (Phase 3).",
        )

    def _cmd_quota(self, args: str) -> CommandResult:
        """Show quota/budget usage — stub, needs API call."""
        total = self._get_total_cost()
        return CommandResult(
            handled=True,
            output=f"Coste acumulado en esta sesion: ${total:.4f}\nPara ver tu presupuesto completo, consulta el panel web.",
        )

    def _cmd_subagent_stub(self, args: str) -> CommandResult:
        """Stub for subagent-related commands (Phase 3)."""
        return CommandResult(
            handled=True,
            output="Subagentes no disponibles aun (Phase 3).",
        )
