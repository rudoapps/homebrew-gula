"""Interactive list selector using prompt_toolkit."""

from __future__ import annotations

import sys
from dataclasses import dataclass
from typing import List, Optional

from prompt_toolkit import Application
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.layout import Layout
from prompt_toolkit.layout.containers import Window
from prompt_toolkit.layout.controls import FormattedTextControl


@dataclass
class SelectOption:
    """A single option in the selector."""

    value: str
    label: str
    description: str = ""
    right_label: str = ""
    disabled: bool = False
    active: bool = False


def select_option(
    options: List[SelectOption],
    title: str = "",
) -> Optional[str]:
    """Show an interactive selector and return the chosen value.

    Args:
        options: List of options to display.
        title: Optional title shown above the list.

    Returns:
        The value of the selected option, or None if cancelled.
    """
    if not options:
        return None

    # Find initial cursor position (active option or first enabled)
    cursor = 0
    for i, opt in enumerate(options):
        if opt.active and not opt.disabled:
            cursor = i
            break

    result: Optional[str] = None

    kb = KeyBindings()

    @kb.add("up")
    @kb.add("k")
    def _up(event):
        nonlocal cursor
        start = cursor
        while True:
            cursor = (cursor - 1) % len(options)
            if not options[cursor].disabled or cursor == start:
                break

    @kb.add("down")
    @kb.add("j")
    def _down(event):
        nonlocal cursor
        start = cursor
        while True:
            cursor = (cursor + 1) % len(options)
            if not options[cursor].disabled or cursor == start:
                break

    @kb.add("enter")
    def _select(event):
        nonlocal result
        if not options[cursor].disabled:
            result = options[cursor].value
        event.app.exit()

    @kb.add("escape")
    @kb.add("q")
    @kb.add("c-c")
    def _cancel(event):
        event.app.exit()

    def _get_text():
        lines = []
        if title:
            lines.append(("bold", f"  {title}\n"))
            lines.append(("", "\n"))

        for i, opt in enumerate(options):
            is_selected = i == cursor
            prefix = " \u276f " if is_selected else "   "

            if opt.disabled:
                lines.append(("ansigray", f"{prefix}{opt.label}"))
                if opt.description:
                    lines.append(("ansigray", f"  {opt.description}"))
                lines.append(("", "\n"))
                continue

            if is_selected:
                lines.append(("bold ansigreen", prefix))
                lines.append(("bold", opt.label))
            else:
                lines.append(("", prefix))
                lines.append(("", opt.label))

            if opt.right_label:
                style = "bold ansigreen" if is_selected else "ansigray"
                lines.append((style, f"  {opt.right_label}"))

            if opt.active:
                lines.append(("ansigreen", "  *"))

            lines.append(("", "\n"))

            if opt.description:
                desc_style = "ansigray"
                lines.append((desc_style, f"     {opt.description}\n"))

        lines.append(("ansigray", "\n  \u2191\u2193 mover \u00b7 enter seleccionar \u00b7 esc cancelar"))
        return lines

    control = FormattedTextControl(_get_text)
    window = Window(content=control, always_hide_cursor=True)
    layout = Layout(window)

    app: Application = Application(
        layout=layout,
        key_bindings=kb,
        full_screen=False,
        output=_create_stderr_output(),
    )
    app.run()

    return result


def _create_stderr_output():
    """Create a prompt_toolkit output that writes to stderr."""
    from prompt_toolkit.output.defaults import create_output
    return create_output(stdout=sys.stderr)
