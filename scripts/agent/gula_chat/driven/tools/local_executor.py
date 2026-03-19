"""Local tool executor — implements each tool in pure Python."""

from __future__ import annotations

import asyncio
import fnmatch
import os
import re
import subprocess
import shutil
from typing import Any, Awaitable, Callable, Dict, List, Optional

from ...application.ports.driven.tool_executor_port import ToolExecutorPort
from ...domain.entities.tool_call import ToolCall
from ...domain.entities.tool_result import ToolResult
from ...domain.entities.tool_metadata import (
    MAX_FILE_SIZE,
    MAX_OUTPUT_LINES,
    MAX_COMMAND_TIMEOUT,
    MAX_SEARCH_RESULTS,
)
from .path_validator import PathValidator
from .file_backup import FileBackup


# Type alias for the approval callback
ApprovalCallback = Callable[[str, str], Awaitable[bool]]


class LocalToolExecutor(ToolExecutorPort):
    """Executes tool calls on the local filesystem and shell.

    Each tool is implemented in pure Python except for run_command and
    git_info which require shell subprocess execution.

    Args:
        path_validator: Validates and resolves file paths.
        file_backup: Creates backups before file modifications.
        request_approval: Async callback that asks the user to approve
                          write/edit/run operations.  Receives (title, detail)
                          and returns True if approved.
    """

    def __init__(
        self,
        path_validator: PathValidator,
        file_backup: FileBackup,
        request_approval: Optional[ApprovalCallback] = None,
    ) -> None:
        self._validator = path_validator
        self._backup = file_backup
        self._request_approval = request_approval

    async def execute(self, tool_call: ToolCall) -> ToolResult:
        """Dispatch a tool call to the appropriate handler.

        Args:
            tool_call: The tool invocation from the model.

        Returns:
            A ToolResult with the output or error.
        """
        dispatch = {
            "read_file": self._read_file,
            "list_files": self._list_files,
            "search_code": self._search_code,
            "write_file": self._write_file,
            "edit_file": self._edit_file,
            "run_command": self._run_command,
            "git_info": self._git_info,
        }

        handler = dispatch.get(tool_call.name)
        if handler is None:
            return ToolResult(
                id=tool_call.id,
                name=tool_call.name,
                output=f"Herramienta desconocida: {tool_call.name}",
                success=False,
            )

        try:
            output = await handler(tool_call.input)
            return ToolResult(
                id=tool_call.id,
                name=tool_call.name,
                output=output,
                success=True,
            )
        except ToolDeniedError as exc:
            return ToolResult(
                id=tool_call.id,
                name=tool_call.name,
                output=str(exc),
                success=False,
            )
        except Exception as exc:
            return ToolResult(
                id=tool_call.id,
                name=tool_call.name,
                output=f"Error ejecutando {tool_call.name}: {exc}",
                success=False,
            )

    # ── Tool implementations ─────────────────────────────────────────────

    async def _read_file(self, inp: Dict[str, Any]) -> str:
        """Read a file with line numbers (cat -n style)."""
        path = inp.get("path", inp.get("file_path", ""))
        if not path:
            raise ValueError("Se requiere el parametro 'path'")

        ok, result = self._validator.validate_read(path)
        if not ok:
            raise ToolDeniedError(result)

        resolved = result
        if not os.path.isfile(resolved):
            raise FileNotFoundError(f"Archivo no encontrado: {path}")

        with open(resolved, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()

        # Handle line range if specified
        start_line = inp.get("start_line")
        end_line = inp.get("end_line")

        lines = content.split("\n")
        total_lines = len(lines)

        if start_line is not None or end_line is not None:
            s = max(1, int(start_line or 1))
            e = min(total_lines, int(end_line or total_lines))
            lines = lines[s - 1:e]
            start_num = s
        else:
            start_num = 1

        # Add line numbers (cat -n style)
        numbered = []
        for i, line in enumerate(lines, start=start_num):
            numbered.append(f"{i:>6}\t{line}")

        output = "\n".join(numbered)

        # Truncate if too large
        if len(output) > MAX_FILE_SIZE:
            output = output[:MAX_FILE_SIZE]
            output += f"\n\n... [truncado, archivo tiene {total_lines} lineas]"

        return output

    async def _list_files(self, inp: Dict[str, Any]) -> str:
        """List files in a directory with optional pattern matching."""
        path = inp.get("path", inp.get("directory", "."))
        pattern = inp.get("pattern", "")
        recursive = inp.get("recursive", True)

        ok, result = self._validator.validate_read(path)
        if not ok:
            raise ToolDeniedError(result)

        resolved = result
        if not os.path.isdir(resolved):
            raise NotADirectoryError(f"No es un directorio: {path}")

        # Load .gitignore patterns if available
        gitignore_patterns = self._load_gitignore(resolved)

        matches: List[str] = []
        cwd = self._validator.working_dir

        if recursive:
            for root, dirs, files in os.walk(resolved):
                # Skip hidden directories and common ignore dirs
                dirs[:] = [
                    d for d in dirs
                    if not d.startswith(".")
                    and d not in ("node_modules", "__pycache__", ".git", "venv", ".venv", "dist", "build")
                    and not self._matches_gitignore(
                        os.path.relpath(os.path.join(root, d), resolved),
                        gitignore_patterns,
                    )
                ]

                for name in files:
                    if name.startswith("."):
                        continue
                    if pattern and not fnmatch.fnmatch(name, pattern):
                        continue

                    full = os.path.join(root, name)
                    rel = os.path.relpath(full, cwd)
                    matches.append(rel)

                    if len(matches) >= MAX_SEARCH_RESULTS:
                        break
                if len(matches) >= MAX_SEARCH_RESULTS:
                    break
        else:
            for entry in sorted(os.listdir(resolved)):
                if entry.startswith("."):
                    continue
                if pattern and not fnmatch.fnmatch(entry, pattern):
                    continue
                full = os.path.join(resolved, entry)
                rel = os.path.relpath(full, cwd)
                suffix = "/" if os.path.isdir(full) else ""
                matches.append(f"{rel}{suffix}")

                if len(matches) >= MAX_SEARCH_RESULTS:
                    break

        if not matches:
            return f"No se encontraron archivos en {path}"

        header = f"{len(matches)} archivos"
        if len(matches) >= MAX_SEARCH_RESULTS:
            header += f" (limitado a {MAX_SEARCH_RESULTS})"

        return f"{header}:\n" + "\n".join(matches)

    async def _search_code(self, inp: Dict[str, Any]) -> str:
        """Search for a pattern in code files using ripgrep or fallback."""
        query = inp.get("pattern", inp.get("query", ""))
        path = inp.get("path", inp.get("directory", "."))
        file_pattern = inp.get("file_pattern", "")
        case_sensitive = inp.get("case_sensitive", True)

        if not query:
            raise ValueError("Se requiere el parametro 'pattern'")

        ok, result = self._validator.validate_read(path)
        if not ok:
            raise ToolDeniedError(result)
        resolved = result

        # Try ripgrep first, fallback to Python
        rg_path = shutil.which("rg")
        if rg_path:
            return await self._search_with_ripgrep(
                rg_path, query, resolved, file_pattern, case_sensitive
            )
        return self._search_with_python(
            query, resolved, file_pattern, case_sensitive
        )

    async def _search_with_ripgrep(
        self,
        rg_path: str,
        query: str,
        directory: str,
        file_pattern: str,
        case_sensitive: bool,
    ) -> str:
        """Run ripgrep subprocess for code search."""
        cmd = [
            rg_path, "--no-heading", "--line-number",
            "--max-count", str(MAX_SEARCH_RESULTS),
            "--max-columns", "200",
            "--max-columns-preview",
        ]

        if not case_sensitive:
            cmd.append("--ignore-case")

        if file_pattern:
            cmd.extend(["--glob", file_pattern])

        cmd.extend([query, directory])

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=15
            )
            output = stdout.decode("utf-8", errors="replace")

            if not output.strip():
                return f'No se encontraron resultados para "{query}"'

            # Make paths relative to cwd
            cwd = self._validator.working_dir
            lines = output.strip().split("\n")
            relative_lines = []
            for line in lines[:MAX_SEARCH_RESULTS]:
                # ripgrep output: /abs/path:line:content
                if directory in line:
                    line = line.replace(directory, os.path.relpath(directory, cwd), 1)
                relative_lines.append(line)

            return "\n".join(relative_lines)

        except asyncio.TimeoutError:
            return "Busqueda cancelada: timeout de 15 segundos"
        except Exception as exc:
            # Fallback to Python search on error
            return self._search_with_python(
                query, directory, file_pattern, case_sensitive
            )

    def _search_with_python(
        self,
        query: str,
        directory: str,
        file_pattern: str,
        case_sensitive: bool,
    ) -> str:
        """Pure Python fallback for code search."""
        flags = 0 if case_sensitive else re.IGNORECASE
        try:
            regex = re.compile(query, flags)
        except re.error:
            regex = re.compile(re.escape(query), flags)

        cwd = self._validator.working_dir
        matches: List[str] = []

        for root, dirs, files in os.walk(directory):
            dirs[:] = [
                d for d in dirs
                if not d.startswith(".")
                and d not in ("node_modules", "__pycache__", ".git", "venv", ".venv")
            ]

            for name in files:
                if name.startswith("."):
                    continue
                if file_pattern and not fnmatch.fnmatch(name, file_pattern):
                    continue

                full = os.path.join(root, name)
                rel = os.path.relpath(full, cwd)

                try:
                    with open(full, "r", encoding="utf-8", errors="ignore") as f:
                        for lineno, line in enumerate(f, 1):
                            if regex.search(line):
                                matches.append(
                                    f"{rel}:{lineno}:{line.rstrip()[:200]}"
                                )
                                if len(matches) >= MAX_SEARCH_RESULTS:
                                    break
                except (OSError, UnicodeDecodeError):
                    continue

                if len(matches) >= MAX_SEARCH_RESULTS:
                    break
            if len(matches) >= MAX_SEARCH_RESULTS:
                break

        if not matches:
            return f'No se encontraron resultados para "{query}"'

        return "\n".join(matches)

    async def _write_file(self, inp: Dict[str, Any]) -> str:
        """Write content to a file, creating directories as needed."""
        path = inp.get("path", inp.get("file_path", ""))
        content = inp.get("content", "")

        if not path:
            raise ValueError("Se requiere el parametro 'path'")

        ok, result = self._validator.validate_write(path)
        if not ok:
            raise ToolDeniedError(result)

        resolved = result
        is_new = not os.path.isfile(resolved)

        # Check approval
        if self._request_approval:
            if is_new:
                preview = content[:500]
                if len(content) > 500:
                    preview += "\n..."
                title = f"Crear {os.path.relpath(resolved, self._validator.working_dir)}"
                detail = f"Nuevo archivo ({len(content)} caracteres):\n{preview}"
            else:
                title = f"Escribir {os.path.relpath(resolved, self._validator.working_dir)}"
                detail = f"Sobreescribir archivo ({len(content)} caracteres)"

                # Extra warning for sensitive files
                sensitive = self._validator.is_sensitive(resolved)
                if sensitive:
                    detail = f"[SENSIBLE: {sensitive}] {detail}"

            approved = await self._request_approval(title, detail)
            if not approved:
                raise ToolDeniedError("Operacion rechazada por el usuario")

        # Create backup of existing file
        if not is_new:
            self._backup.create_backup(resolved)

        # Create parent directories if needed
        parent = os.path.dirname(resolved)
        if parent:
            os.makedirs(parent, exist_ok=True)

        # Write the file
        with open(resolved, "w", encoding="utf-8") as f:
            f.write(content)

        rel = os.path.relpath(resolved, self._validator.working_dir)
        lines = content.count("\n") + 1
        if is_new:
            return f"Archivo creado: {rel} ({lines} lineas)"
        return f"Archivo escrito: {rel} ({lines} lineas)"

    async def _edit_file(self, inp: Dict[str, Any]) -> str:
        """Apply an old_string -> new_string replacement to a file."""
        path = inp.get("path", inp.get("file_path", ""))
        old_string = inp.get("old_string", "")
        new_string = inp.get("new_string", "")

        if not path:
            raise ValueError("Se requiere el parametro 'path'")
        if not old_string:
            raise ValueError("Se requiere el parametro 'old_string'")

        ok, result = self._validator.validate_write(path)
        if not ok:
            raise ToolDeniedError(result)

        resolved = result
        if not os.path.isfile(resolved):
            raise FileNotFoundError(f"Archivo no encontrado: {path}")

        # Read current content
        with open(resolved, "r", encoding="utf-8", errors="replace") as f:
            current = f.read()

        # Check that old_string exists
        count = current.count(old_string)
        if count == 0:
            raise ValueError(
                f"old_string no encontrado en {path}. "
                f"Verifica que el texto coincida exactamente."
            )

        # Apply replacement
        new_content = current.replace(old_string, new_string, 1)

        # Calculate diff stats
        old_lines = old_string.count("\n") + 1
        new_lines = new_string.count("\n") + 1
        added = max(0, new_lines - old_lines)
        removed = max(0, old_lines - new_lines)

        # Check approval
        if self._request_approval:
            rel = os.path.relpath(resolved, self._validator.working_dir)
            title = f"Editar {rel}  +{added}/-{removed} lineas"
            detail = _build_diff_detail(old_string, new_string)

            sensitive = self._validator.is_sensitive(resolved)
            if sensitive:
                detail = f"[SENSIBLE: {sensitive}]\n{detail}"

            approved = await self._request_approval(title, detail)
            if not approved:
                raise ToolDeniedError("Operacion rechazada por el usuario")

        # Create backup
        self._backup.create_backup(resolved)

        # Write modified content
        with open(resolved, "w", encoding="utf-8") as f:
            f.write(new_content)

        rel = os.path.relpath(resolved, self._validator.working_dir)
        return (
            f"Archivo editado: {rel} "
            f"(+{added}/-{removed} lineas, {count} coincidencia(s))"
        )

    async def _run_command(self, inp: Dict[str, Any]) -> str:
        """Execute a shell command with timeout and output capture."""
        command = inp.get("command", "")
        timeout = min(
            int(inp.get("timeout", MAX_COMMAND_TIMEOUT)),
            MAX_COMMAND_TIMEOUT,
        )

        if not command:
            raise ValueError("Se requiere el parametro 'command'")

        # Check approval
        if self._request_approval:
            approved = await self._request_approval(
                f"Ejecutar comando",
                f"$ {command}\n(timeout: {timeout}s)",
            )
            if not approved:
                raise ToolDeniedError("Operacion rechazada por el usuario")

        try:
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=self._validator.working_dir,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=timeout
            )
        except asyncio.TimeoutError:
            try:
                proc.kill()
            except ProcessLookupError:
                pass
            return f"Comando cancelado: timeout de {timeout} segundos"

        output_parts: List[str] = []

        stdout_text = stdout.decode("utf-8", errors="replace")
        stderr_text = stderr.decode("utf-8", errors="replace")

        if stdout_text.strip():
            output_parts.append(stdout_text)
        if stderr_text.strip():
            output_parts.append(f"[stderr]\n{stderr_text}")

        output = "\n".join(output_parts)

        # Truncate if too many lines
        lines = output.split("\n")
        if len(lines) > MAX_OUTPUT_LINES:
            output = "\n".join(lines[:MAX_OUTPUT_LINES])
            output += f"\n\n... [truncado, {len(lines)} lineas totales]"

        exit_code = proc.returncode
        if exit_code != 0:
            output += f"\n\n[exit code: {exit_code}]"

        return output if output.strip() else f"Comando completado (exit code: {exit_code})"

    async def _git_info(self, inp: Dict[str, Any]) -> str:
        """Run git info commands and return output."""
        subcommand = inp.get("command", inp.get("subcommand", "status"))

        # Map of allowed git subcommands
        allowed: Dict[str, List[str]] = {
            "status": ["git", "status", "--porcelain", "-b"],
            "log": ["git", "log", "--oneline", "-20"],
            "diff": ["git", "diff", "--stat"],
            "diff_staged": ["git", "diff", "--staged", "--stat"],
            "branch": ["git", "branch", "-a"],
            "blame": [],  # needs file arg
            "show": ["git", "show", "--stat", "HEAD"],
            "remote": ["git", "remote", "-v"],
        }

        if subcommand == "blame":
            file_path = inp.get("file", inp.get("path", ""))
            if not file_path:
                raise ValueError("git blame requiere el parametro 'file'")
            ok, resolved = self._validator.validate_read(file_path)
            if not ok:
                raise ToolDeniedError(resolved)
            cmd = ["git", "blame", "--line-porcelain", resolved]
        elif subcommand in allowed:
            cmd = allowed[subcommand]
            if not cmd:
                raise ValueError(f"Subcomando git no soportado: {subcommand}")
        else:
            raise ValueError(
                f"Subcomando git no permitido: {subcommand}. "
                f"Opciones: {', '.join(allowed.keys())}"
            )

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=self._validator.working_dir,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=10
            )
        except asyncio.TimeoutError:
            return f"git {subcommand}: timeout de 10 segundos"
        except FileNotFoundError:
            return "git no esta instalado o no esta en el PATH"

        output = stdout.decode("utf-8", errors="replace")
        if proc.returncode != 0:
            err = stderr.decode("utf-8", errors="replace")
            return f"git {subcommand} error:\n{err}"

        # Truncate
        lines = output.split("\n")
        if len(lines) > MAX_OUTPUT_LINES:
            output = "\n".join(lines[:MAX_OUTPUT_LINES])
            output += f"\n... [truncado]"

        return output if output.strip() else f"git {subcommand}: sin salida"

    # ── Helpers ──────────────────────────────────────────────────────────

    @staticmethod
    def _load_gitignore(directory: str) -> List[str]:
        """Load .gitignore patterns from a directory."""
        gitignore_path = os.path.join(directory, ".gitignore")
        if not os.path.isfile(gitignore_path):
            return []
        try:
            with open(gitignore_path, "r", encoding="utf-8") as f:
                return [
                    line.strip()
                    for line in f
                    if line.strip() and not line.startswith("#")
                ]
        except OSError:
            return []

    @staticmethod
    def _matches_gitignore(rel_path: str, patterns: List[str]) -> bool:
        """Check if a relative path matches any gitignore pattern."""
        for pattern in patterns:
            if fnmatch.fnmatch(rel_path, pattern):
                return True
            if fnmatch.fnmatch(os.path.basename(rel_path), pattern):
                return True
        return False


class ToolDeniedError(Exception):
    """Raised when a tool operation is denied (security or user rejection)."""


def _build_diff_detail(old: str, new: str) -> str:
    """Build a compact diff display for edit approval."""
    old_lines = old.split("\n")
    new_lines = new.split("\n")

    parts: List[str] = []

    # Show removed lines
    for line in old_lines:
        parts.append(f"  - {line}")

    # Show added lines
    for line in new_lines:
        parts.append(f"  + {line}")

    # Limit display
    if len(parts) > 30:
        parts = parts[:30]
        parts.append("  ... (truncado)")

    return "\n".join(parts)
