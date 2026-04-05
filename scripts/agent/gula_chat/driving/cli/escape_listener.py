"""Background Esc key listener for aborting agent execution.

Runs a thread that reads raw stdin for Esc (0x1b) presses.
Sets a flag that the main loop checks between iterations.
"""

from __future__ import annotations

import sys
import threading
from typing import Optional


class EscapeListener:
    """Listens for Esc key in a background thread."""

    def __init__(self) -> None:
        self._abort = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self._running = False

    @property
    def abort_requested(self) -> bool:
        return self._abort.is_set()

    def start(self) -> None:
        """Start listening for Esc in background."""
        self._abort.clear()
        self._running = True
        self._thread = threading.Thread(target=self._listen, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        """Stop the listener."""
        self._running = False
        self._abort.clear()
        self._thread = None

    def reset(self) -> None:
        """Clear the abort flag without stopping the listener."""
        self._abort.clear()

    def _listen(self) -> None:
        """Read raw bytes from stdin looking for Esc (0x1b)."""
        import tty
        import termios

        fd = sys.stdin.fileno()
        try:
            old_settings = termios.tcgetattr(fd)
        except termios.error:
            return  # Not a real terminal

        try:
            tty.setcbreak(fd)
            while self._running:
                try:
                    ch = sys.stdin.read(1)
                    if ch == '\x1b':  # Esc
                        self._abort.set()
                        break
                except (IOError, OSError):
                    break
        finally:
            try:
                termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
            except termios.error:
                pass
