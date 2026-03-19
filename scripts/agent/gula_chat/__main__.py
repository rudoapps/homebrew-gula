"""Entry point for `python3 -m gula_chat`."""

import sys

from .container import Container
from .driving.cli.app import App


def main() -> int:
    debug = "--debug" in sys.argv
    container = Container(debug=debug)
    app = App(container)
    return app.run()


if __name__ == "__main__":
    sys.exit(main())
