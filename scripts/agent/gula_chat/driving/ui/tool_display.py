"""Tool execution display — renders tool progress and approval prompts."""

from __future__ import annotations

import time
from typing import Any, Dict

from ...domain.entities.tool_metadata import get_tool_detail
from .console import get_console
from .spinner import Spinner


class ToolDisplay:
    """Renders tool execution progress to the terminal.

    Provides visual feedback for tool starts, completions, parallel
    summaries, approval prompts, and diff displays.
    """

    def __init__(self) -> None:
        self._console = get_console()
        self._spinner = Spinner()

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

        Displays the operation detail and asks the user to confirm with y/n.

        Args:
            tool_name: The tool requesting approval.
            detail: Description of what the tool wants to do.

        Returns:
            True if the user approved, False otherwise.
        """
        self._spinner.stop()
        self._console.print()

        # Show the operation detail
        for line in detail.split("\n"):
            if line.startswith("  - "):
                self._console.print(f"  [red]{line}[/red]")
            elif line.startswith("  + "):
                self._console.print(f"  [green]{line}[/green]")
            else:
                self._console.print(f"  [dim]{line}[/dim]")

        self._console.print()

        # Simple y/n prompt
        try:
            import sys
            self._console.print(
                "  [bold]Aprobar? (s/n):[/bold] ",
                end="",
            )
            # Flush stderr since console writes to stderr
            sys.stderr.flush()

            # Read from stdin (which is the real terminal)
            response = input().strip().lower()
            return response in ("s", "si", "y", "yes")
        except (EOFError, KeyboardInterrupt):
            self._console.print("  [dim]Cancelado[/dim]")
            return False

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
