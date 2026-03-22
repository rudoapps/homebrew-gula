"""Gula Chat - Clean Architecture CLI for the Gula Agent API."""

import os as _os


def _read_version() -> str:
    """Read version from the VERSION file at repo root."""
    # Navigate from gula_chat/ -> agent/ -> scripts/ -> gula/VERSION
    _here = _os.path.dirname(_os.path.abspath(__file__))
    for _rel in (
        _os.path.join(_here, "..", "..", "..", "VERSION"),       # scripts/agent/gula_chat -> gula/VERSION
        _os.path.join(_here, "..", "..", "..", "..", "VERSION"), # extra level just in case
    ):
        _path = _os.path.normpath(_rel)
        if _os.path.isfile(_path):
            with open(_path) as _f:
                return _f.read().strip()
    return "dev"


__version__ = _read_version()
