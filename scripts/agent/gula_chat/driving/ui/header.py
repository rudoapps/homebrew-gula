"""Session header display for interactive mode."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from .console import get_console

# Style mapping for broadcast message types
_MESSAGE_STYLES: Dict[str, str] = {
    "info": "cyan",
    "warning": "yellow",
    "success": "green",
    "error": "red bold",
}

_MESSAGE_ICONS: Dict[str, str] = {
    "info": "\u2139",      # ℹ
    "warning": "\u26a0",   # ⚠
    "success": "\u2713",   # ✓
    "error": "\u2717",     # ✗
}


class SessionHeader:
    """Renders the interactive session header banner.

    Shows project name, conversation info, and available shortcuts
    using the Rich console with gula theme styling.
    """

    def __init__(self) -> None:
        self._console = get_console()

    def show(
        self,
        project_name: str,
        conversation_id: Optional[int] = None,
        rag_status: Optional[str] = None,
        broadcast_messages: Optional[List[Dict[str, Any]]] = None,
    ) -> None:
        """Display the session header banner.

        Args:
            project_name: Name of the current project (typically git repo name).
            conversation_id: Current conversation ID, or None for new.
            rag_status: RAG status string, or None if not available.
            broadcast_messages: List of broadcast message dicts from the API.
        """
        self._console.print()
        self._console.rule(style="dim")

        # Project line
        parts = [f"[agent.header]{project_name}[/agent.header]"]

        if conversation_id is not None:
            parts.append(f"[dim]conversacion #{conversation_id}[/dim]")

        if rag_status:
            parts.append(f"[agent.rag]{rag_status}[/agent.rag]")

        line = " \u00b7 ".join(parts)
        self._console.print(f"  {line}")

        # Shortcuts line
        self._console.print(
            "  [dim]/new nueva conversacion \u00b7 /help comandos[/dim]"
        )

        self._console.rule(style="dim")

        # Broadcast messages (after header, before prompt)
        if broadcast_messages:
            self._console.print()
            for msg in broadcast_messages:
                self._render_broadcast(msg)

        self._console.print()

    def _render_broadcast(self, msg: Dict[str, Any]) -> None:
        """Render a single broadcast message with appropriate styling."""
        msg_type = msg.get("message_type", "info")
        text = msg.get("message", "")
        style = _MESSAGE_STYLES.get(msg_type, "cyan")
        icon = _MESSAGE_ICONS.get(msg_type, "\u2139")
        self._console.print(f"  [{style}]{icon} {text}[/{style}]")

    def show_new_conversation(self) -> None:
        """Display a brief banner when starting a new conversation."""
        self._console.print()
        self._console.print("  [success]\u2713[/success] Nueva conversacion iniciada")
        self._console.print()

    def show_resumed_conversation(self, conversation_id: int) -> None:
        """Display a brief banner when resuming an existing conversation.

        Args:
            conversation_id: The conversation ID being resumed.
        """
        self._console.print()
        self._console.print(
            f"  [info]\u2139[/info] Retomando conversacion #{conversation_id}"
        )
        self._console.print()
