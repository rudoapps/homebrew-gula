"""Path validation for tool operations — security boundary."""

from __future__ import annotations

import os
from typing import Optional, Tuple

from ...domain.entities.tool_metadata import (
    BLOCKED_FILE_EXTENSIONS,
    BLOCKED_FILE_NAMES,
    SENSITIVE_PATTERNS,
)


class PathValidator:
    """Validates and resolves file paths for tool operations.

    All paths are validated against the working directory to prevent
    directory traversal attacks.  Blocked extensions and names are
    rejected outright.

    Args:
        working_dir: The root directory that all paths must resolve within.
                     Defaults to os.getcwd() at construction time.
    """

    def __init__(self, working_dir: Optional[str] = None) -> None:
        self._working_dir = os.path.realpath(working_dir or os.getcwd())

    @property
    def working_dir(self) -> str:
        """The resolved working directory."""
        return self._working_dir

    def validate_read(self, path: str) -> Tuple[bool, str]:
        """Validate a path for reading.

        Resolves the path, checks it is within the working directory,
        and verifies it is not a blocked file type.

        Args:
            path: The raw path from the tool call.

        Returns:
            A tuple of (ok, result) where result is the resolved absolute
            path on success, or an error message on failure.
        """
        resolved = self._resolve(path)

        # Must be within working directory
        if not self._is_within_cwd(resolved):
            return False, (
                f"Acceso denegado: la ruta '{path}' esta fuera del "
                f"directorio de trabajo ({self._working_dir})"
            )

        # Check blocked extensions
        _, ext = os.path.splitext(resolved)
        if ext.lower() in BLOCKED_FILE_EXTENSIONS:
            return False, (
                f"Acceso denegado: extension '{ext}' esta bloqueada "
                f"por motivos de seguridad"
            )

        # Check blocked file names
        basename = os.path.basename(resolved)
        rel = os.path.relpath(resolved, self._working_dir)
        for blocked in BLOCKED_FILE_NAMES:
            if basename == blocked or rel.endswith(blocked):
                return False, (
                    f"Acceso denegado: el archivo '{basename}' esta "
                    f"bloqueado por motivos de seguridad"
                )

        return True, resolved

    def validate_write(self, path: str) -> Tuple[bool, str]:
        """Validate a path for writing.

        In addition to read validations, checks that the parent
        directory exists or can be created.

        Args:
            path: The raw path from the tool call.

        Returns:
            A tuple of (ok, result) where result is the resolved absolute
            path on success, or an error message on failure.
        """
        # First apply read validations
        ok, result = self.validate_read(path)
        if not ok:
            return ok, result

        resolved = result

        # Check parent directory
        parent = os.path.dirname(resolved)
        if not os.path.isdir(parent):
            # Try to determine if parent can be created
            # Walk up until we find an existing directory
            check = parent
            while check and not os.path.isdir(check):
                check = os.path.dirname(check)
            if not check or not self._is_within_cwd(check):
                return False, (
                    f"No se puede crear el directorio padre: '{parent}'"
                )

        return True, resolved

    def is_sensitive(self, path: str) -> Optional[str]:
        """Check whether a file path matches a sensitive pattern.

        Args:
            path: An already-resolved absolute path.

        Returns:
            A reason string if the file is sensitive and needs explicit
            approval, or None if the file is safe to modify.
        """
        basename = os.path.basename(path)
        rel = os.path.relpath(path, self._working_dir)

        for pattern in SENSITIVE_PATTERNS:
            if pattern in basename or pattern in rel:
                return (
                    f"'{basename}' coincide con patron sensible '{pattern}'"
                )

        return None

    # ── Internal helpers ─────────────────────────────────────────────────

    def _resolve(self, path: str) -> str:
        """Resolve a path to an absolute path relative to the working dir."""
        if os.path.isabs(path):
            return os.path.realpath(path)
        return os.path.realpath(os.path.join(self._working_dir, path))

    def _is_within_cwd(self, resolved_path: str) -> bool:
        """Check that a resolved path is within the working directory."""
        try:
            common = os.path.commonpath([self._working_dir, resolved_path])
            return common == self._working_dir
        except ValueError:
            # Different drives on Windows
            return False
