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
        output: str = "",
    ) -> None:
        """Show that a tool has finished executing.

        Args:
            name: Tool name.
            input_dict: The tool input parameters.
            success: Whether the tool succeeded.
            elapsed: Time taken in seconds.
            output: The tool's output text (for summary extraction).
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

        # Show summary for run_command results
        if name == "run_command" and output:
            summary = _extract_command_summary(output)
            if summary:
                self._console.print(f"  [dim]  {summary}[/dim]")

        # Show compact edit details for edit_file / write_file so the
        # user can see WHAT changed even in auto-approve mode.
        if name in ("edit_file", "write_file") and output and success:
            edit_summary = _extract_edit_summary(output)
            if edit_summary:
                for line in edit_summary:
                    self._console.print(f"  [dim]  {line}[/dim]")

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

        # Show the operation detail (diff lines / script content)
        in_script_block = False
        for line in detail.split("\n"):
            if line.startswith("── contenido del script"):
                in_script_block = True
                self._console.print(f"  [bold cyan]{line}[/bold cyan]")
            elif in_script_block:
                # Script content — show with syntax coloring hint
                self._console.print(f"  [yellow]{line}[/yellow]")
            elif line.startswith("  - "):
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
                    # Render selector line with descriptions inline
                    line_parts = []
                    for i, (_, label, color, desc) in enumerate(options):
                        if i == selected:
                            line_parts.append(
                                f"\033[1m❯ {label}\033[0m \033[2m({desc})\033[0m"
                            )
                        else:
                            line_parts.append(f"\033[2m  {label}\033[0m")

                    selector_line = "  " + "   ".join(line_parts)
                    sys.stderr.write(f"\r\033[K{selector_line}")
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

        # Clear line and show result
        sys.stderr.write(f"\r\033[K\033[?25h")
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
        output: str = "",
    ) -> None:
        """Alias for show_tool_complete (ToolProgressCallback protocol)."""
        self.show_tool_complete(name, input_dict, success, elapsed, output)

        # OS notification for long commands (>30s)
        if name == "run_command" and elapsed > 30:
            try:
                from ...driven.notifications.os_notify import send_notification
                status = "completado" if success else "fallido"
                cmd = input_dict.get("command", "")[:50]
                send_notification(
                    f"gula - Comando {status}",
                    f"{cmd} ({elapsed:.0f}s)",
                )
            except Exception:
                pass

    def on_parallel_summary(
        self,
        count: int,
        elapsed: float,
        has_errors: bool,
    ) -> None:
        """Alias for show_parallel_summary (ToolProgressCallback protocol)."""
        self.show_parallel_summary(count, elapsed, has_errors)

    def on_multi_file_preview(self, count: int, summary: str) -> None:
        """Show preview of multiple file edits before execution."""
        self._console.print()
        self._console.print(f"  [bold cyan]\u2139 {count} archivos a modificar:[/bold cyan]")
        for line in summary.strip().split("\n"):
            self._console.print(f"  [dim]{line.strip()}[/dim]")


def _extract_edit_summary(output: str) -> list[str]:
    """Extract a compact summary of an edit_file / write_file result.

    For edit_file (which now includes post-edit context lines marked with
    '>'), returns those modified lines so the user sees WHAT changed at a
    glance — even in auto-approve mode where the diff dialog was skipped.

    For write_file, returns the first 3 lines of the new file content.

    Returns:
        A list of display lines (max ~5), or [] if nothing useful.
    """
    lines = output.split("\n")

    # edit_file with post-edit context — look for '>' marked lines
    modified = [
        l.strip()
        for l in lines
        if len(l) > 3 and l.lstrip()[:1].isdigit() and ">" in l
    ]
    if modified:
        # Show up to 5 modified lines
        result = modified[:5]
        remaining = len(modified) - 5
        if remaining > 0:
            result.append(f"... (+{remaining} lineas modificadas)")
        return result

    # write_file — show first 3 content lines (skip the "Archivo creado" header)
    content_lines = [l for l in lines[1:] if l.strip()]
    if content_lines:
        preview = content_lines[:3]
        if len(content_lines) > 3:
            preview.append("...")
        return preview

    return []


def _extract_command_summary(output: str) -> str:
    """Extract a one-line summary from command output.

    Platform-agnostic: shows the last meaningful line of output
    and the exit code if non-zero.
    """
    import re

    lines = output.strip().split("\n")
    if not lines:
        return ""

    # Check for exit code
    exit_code = None
    last_line = lines[-1].strip()
    m = re.search(r"\[exit code: (\d+)\]", last_line)
    if m:
        exit_code = int(m.group(1))
        lines = lines[:-1]  # remove exit code line

    # Find last non-empty, non-bracket line
    summary_line = ""
    for line in reversed(lines):
        line = line.strip()
        if line and not line.startswith("["):
            summary_line = line[:80]
            break

    if exit_code is not None and exit_code != 0:
        if summary_line:
            return f"{summary_line} (exit {exit_code})"
        return f"exit code {exit_code}"

    if summary_line:
        return summary_line

    return ""
