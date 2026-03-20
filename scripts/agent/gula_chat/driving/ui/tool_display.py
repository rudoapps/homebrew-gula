"""Tool execution display — renders tool progress and approval prompts."""

from __future__ import annotations

import sys
import time
from typing import Any, Dict

from ...domain.entities.tool_metadata import get_tool_detail
from .console import get_console
from .spinner import Spinner

# Approval choices
_ALLOW = "allow"
_ALLOW_ALWAYS = "allow_always"
_REJECT = "reject"


class ToolDisplay:
    """Renders tool execution progress to the terminal.

    Provides visual feedback for tool starts, completions, parallel
    summaries, approval prompts, and diff displays.
    """

    def __init__(self) -> None:
        self._console = get_console()
        self._spinner = Spinner()
        self._auto_approve_turn: bool = False

    def show_tool_start(self, name: str, input_dict: Dict[str, Any]) -> None:
        """Show that a tool is about to start executing.

        Args:
            name: Tool name (e.g. "read_file").
            input_dict: The tool input parameters.
        """
        icon, verb, detail, action_msg = get_tool_detail(name, input_dict)
        self._spinner.start(f"{icon} {action_msg}")

    def show_tool_complete(
        self,
        name: str,
        input_dict: Dict[str, Any],
        success: bool,
        elapsed: float,
    ) -> None:
        """Show that a tool has finished executing.

        Args:
            name: Tool name.
            input_dict: The tool input parameters.
            success: Whether the tool succeeded.
            elapsed: Time taken in seconds.
        """
        icon, verb, detail, action_msg = get_tool_detail(name, input_dict)
        elapsed_str = f"{elapsed:.1f}s" if elapsed >= 0.1 else "<0.1s"

        self._spinner.stop()

        if success:
            self._console.print(
                f"  [success]\u2713[/success] [agent.tool]{action_msg}[/agent.tool] "
                f"[dim]({elapsed_str})[/dim]"
            )
        else:
            self._console.print(
                f"  [error]\u2717[/error] [agent.tool]{action_msg}[/agent.tool] "
                f"[dim]({elapsed_str})[/dim]"
            )

    def show_parallel_summary(
        self,
        count: int,
        elapsed: float,
        has_errors: bool,
    ) -> None:
        """Show a summary after a batch of parallel tools completes.

        Args:
            count: Number of tools that ran in parallel.
            elapsed: Total time for the parallel batch.
            has_errors: Whether any tool in the batch failed.
        """
        self._spinner.stop()
        elapsed_str = f"{elapsed:.1f}s"

        if has_errors:
            self._console.print(
                f"  [warning]\u25cb[/warning] [agent.tool]{count} herramientas "
                f"en paralelo[/agent.tool] [dim]({elapsed_str}, con errores)[/dim]"
            )
        else:
            self._console.print(
                f"  [success]\u2713[/success] [agent.tool]{count} herramientas "
                f"en paralelo[/agent.tool] [dim]({elapsed_str})[/dim]"
            )

    async def show_approval_prompt(
        self,
        tool_name: str,
        detail: str,
    ) -> bool:
        """Show an interactive approval prompt for a write/edit/run operation.

        Displays the operation detail and a selector for the user to choose
        between allow, allow always, or reject.

        Args:
            tool_name: The tool requesting approval.
            detail: Description of what the tool wants to do.

        Returns:
            True if the user approved, False otherwise.
        """
        self._spinner.stop()

        # Auto-approve if user selected "Permitir todo el turno"
        if self._auto_approve_turn:
            self._console.print(
                f"  [dim](auto-aprobado este turno)[/dim]"
            )
            return True

        self._console.print()

        # Show the operation detail (diff lines)
        for line in detail.split("\n"):
            if line.startswith("  - "):
                self._console.print(f"  [red]{line}[/red]")
            elif line.startswith("  + "):
                self._console.print(f"  [green]{line}[/green]")
            elif line.lstrip().startswith("@@"):
                self._console.print(f"  [cyan]{line}[/cyan]")
            else:
                self._console.print(f"  [dim]{line}[/dim]")

        self._console.print()

        # Interactive selector
        result = self._show_selector(tool_name)

        if result == _ALLOW_ALWAYS:
            self._auto_approve_turn = True
            return True

        return result == _ALLOW

    def reset_turn_approval(self) -> None:
        """Reset auto-approval at the start of a new turn."""
        self._auto_approve_turn = False

    def _show_selector(self, tool_name: str) -> str:
        """Show an interactive selector using keyboard arrows.

        Returns:
            One of _ALLOW, _ALLOW_ALWAYS, or _REJECT.
        """
        options = [
            (_ALLOW, "Permitir", "green", "solo esta accion"),
            (_ALLOW_ALWAYS, "Permitir todo", "cyan", "resto del turno sin preguntar"),
            (_REJECT, "Rechazar", "red", "cancelar esta accion"),
        ]
        selected = 0

        # Hide cursor
        sys.stderr.write("\033[?25l")
        sys.stderr.flush()

        try:
            import tty
            import termios

            fd = sys.stdin.fileno()
            old_settings = termios.tcgetattr(fd)
            tty.setraw(fd)

            try:
                while True:
                    # Render selector line
                    line_parts = []
                    for i, (_, label, color, _desc) in enumerate(options):
                        if i == selected:
                            line_parts.append(f"\033[1m❯ {label}\033[0m")
                        else:
                            line_parts.append(f"\033[2m  {label}\033[0m")

                    # Render description of selected option below
                    _, _, _, desc = options[selected]
                    selector_line = "  " + "    ".join(line_parts)
                    desc_line = f"  \033[2m  {desc}\033[0m"

                    sys.stderr.write(f"\r\033[K{selector_line}\n\033[K{desc_line}\033[A")
                    sys.stderr.flush()

                    # Read key
                    ch = sys.stdin.read(1)
                    if ch == "\r" or ch == "\n":
                        break
                    elif ch == "\x1b":
                        seq = sys.stdin.read(2)
                        if seq == "[D":  # Left arrow
                            selected = max(0, selected - 1)
                        elif seq == "[C":  # Right arrow
                            selected = min(len(options) - 1, selected + 1)
                    elif ch == "q" or ch == "\x03":  # q or Ctrl+C
                        selected = 2  # Reject
                        break
            finally:
                termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

        except (ImportError, OSError, ValueError):
            # Fallback to simple input if terminal control unavailable
            sys.stderr.write("\033[?25h")
            sys.stderr.flush()
            return self._show_simple_prompt()

        # Clear both lines (selector + description) and show result
        sys.stderr.write(f"\r\033[K\n\033[K\033[A\r\033[K\033[?25h")
        sys.stderr.flush()

        choice_value, choice_label, choice_color, _desc = options[selected]
        self._console.print(f"  [{choice_color}]{choice_label}[/{choice_color}]")

        return choice_value

    def _show_simple_prompt(self) -> str:
        """Fallback simple text prompt."""
        self._console.print(
            "  [bold]Permitir (s), Siempre (a), Rechazar (n):[/bold] ",
            end="",
        )
        sys.stderr.flush()
        try:
            response = input().strip().lower()
            if response in ("a", "always", "siempre", "todo"):
                return _ALLOW_ALWAYS
            elif response in ("s", "si", "y", "yes"):
                return _ALLOW
            return _REJECT
        except (EOFError, KeyboardInterrupt):
            self._console.print("  [dim]Cancelado[/dim]")
            return _REJECT

    def show_diff(
        self,
        old_content: str,
        new_content: str,
        filename: str,
    ) -> None:
        """Display a colored diff between old and new content.

        Args:
            old_content: The original file content (or snippet).
            new_content: The modified content (or snippet).
            filename: The filename for the header.
        """
        self._spinner.stop()

        old_lines = old_content.split("\n")
        new_lines = new_content.split("\n")

        added = max(0, len(new_lines) - len(old_lines))
        removed = max(0, len(old_lines) - len(new_lines))

        self._console.print(
            f"  [bold]\u25c9 Update({filename})[/bold]  "
            f"[green]+{added}[/green]/[red]-{removed}[/red] lineas"
        )

        for line in old_lines:
            self._console.print(f"    [red]{line}[/red]")
        for line in new_lines:
            self._console.print(f"    [green]{line}[/green]")

    # ── Protocol aliases for ToolProgressCallback ────────────────────────

    def on_tool_start(self, name: str, input_dict: Dict[str, Any]) -> None:
        """Alias for show_tool_start (ToolProgressCallback protocol)."""
        self.show_tool_start(name, input_dict)

    def on_tool_complete(
        self,
        name: str,
        input_dict: Dict[str, Any],
        success: bool,
        elapsed: float,
    ) -> None:
        """Alias for show_tool_complete (ToolProgressCallback protocol)."""
        self.show_tool_complete(name, input_dict, success, elapsed)

    def on_parallel_summary(
        self,
        count: int,
        elapsed: float,
        has_errors: bool,
    ) -> None:
        """Alias for show_parallel_summary (ToolProgressCallback protocol)."""
        self.show_parallel_summary(count, elapsed, has_errors)
