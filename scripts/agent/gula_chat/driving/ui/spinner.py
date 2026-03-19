"""Spinner wrapper using rich.status.Status."""

from __future__ import annotations

from typing import Optional

from rich.status import Status

from .console import get_console


class Spinner:
    """A managed spinner for showing progress during async operations.

    Wraps rich.status.Status to provide start/stop/update semantics
    matching the existing gula agent UX.
    """

    def __init__(self) -> None:
        self._status: Optional[Status] = None
        self._console = get_console()

    @property
    def is_running(self) -> bool:
        """Return True if the spinner is currently visible."""
        return self._status is not None

    def start(self, message: str = "Procesando...") -> None:
        """Start the spinner with the given message."""
        self.stop()  # Ensure any existing spinner is cleaned up
        self._status = self._console.status(
            f"  [spinner]{message}[/spinner]",
            spinner="dots",
            spinner_style="cyan",
        )
        self._status.start()

    def update(self, message: str) -> None:
        """Update the spinner message."""
        if self._status is not None:
            self._status.update(f"  [spinner]{message}[/spinner]")

    def stop(self, final_message: Optional[str] = None, status: str = "success") -> None:
        """Stop the spinner and optionally display a final status line.

        Args:
            final_message: Optional message to show after stopping.
            status: One of "success", "error", "info" — controls the icon.
        """
        if self._status is not None:
            self._status.stop()
            self._status = None

        if final_message:
            icons = {
                "success": "[success]\u2713[/success]",
                "error": "[error]\u2717[/error]",
                "info": "[info]\u2139[/info]",
            }
            icon = icons.get(status, icons["info"])
            self._console.print(f"  {icon} {final_message}")
