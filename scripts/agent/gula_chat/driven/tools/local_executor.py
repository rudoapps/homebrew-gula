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
    MAX_COMMAND_TIMEOUT_HARD,
    MAX_SEARCH_RESULTS,
)
from .path_validator import PathValidator, OutsideAllowedDirError
from .file_backup import FileBackup
from ...domain.entities.permission_mode import PermissionMode


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
        self._permission_mode = PermissionMode.ASK

    def set_permission_mode(self, mode: PermissionMode) -> None:
        """Change the permission mode."""
        self._permission_mode = mode

    @property
    def permission_mode(self) -> PermissionMode:
        return self._permission_mode

    async def _check_approval(self, title: str, detail: str) -> bool:
        """Check approval based on current permission mode."""
        if self._permission_mode == PermissionMode.AUTO:
            return True
        if self._permission_mode == PermissionMode.PLAN:
            raise ToolDeniedError(f"[PLAN] {title}\n{detail}")
        if self._request_approval:
            return await self._check_approval(title, detail)
        return True

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
            "grep": self._grep,
            "write_file": self._write_file,
            "edit_file": self._edit_file,
            "run_command": self._run_command,
            "git_info": self._git_info,
            "web_fetch": self._web_fetch,
            "find_and_replace": self._find_and_replace,
            "file_diff": self._file_diff,
            "move_file": self._move_file,
            "undo_edit": self._undo_edit,
            "symbols": self._symbols,
            "find_definition": self._find_definition,
            "find_references": self._find_references,
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
        except OutsideAllowedDirError as exc:
            # Ask user for permission to access the directory
            granted = await self._request_dir_access(exc)
            if granted:
                # Retry the operation now that the dir is allowed
                try:
                    output = await handler(tool_call.input)
                    return ToolResult(
                        id=tool_call.id,
                        name=tool_call.name,
                        output=output,
                        success=True,
                    )
                except Exception as retry_exc:
                    return ToolResult(
                        id=tool_call.id,
                        name=tool_call.name,
                        output=f"Error ejecutando {tool_call.name}: {retry_exc}",
                        success=False,
                    )
            return ToolResult(
                id=tool_call.id,
                name=tool_call.name,
                output=(
                    f"Acceso denegado: el usuario no permitio acceder a "
                    f"'{exc.requested_dir}'"
                ),
                success=False,
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
        """Read a file with line numbers (cat -n style). Supports offset/limit."""
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

        lines = content.split("\n")
        total_lines = len(lines)

        # Support offset/limit (1-based) and legacy start_line/end_line
        offset = inp.get("offset") or inp.get("start_line")
        limit = inp.get("limit")
        end_line = inp.get("end_line")

        if offset is not None or limit is not None or end_line is not None:
            s = max(1, int(offset or 1))
            if limit is not None:
                e = min(total_lines, s + int(limit) - 1)
            elif end_line is not None:
                e = min(total_lines, int(end_line))
            else:
                e = total_lines
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

        # Sort by modification time (most recent first)
        try:
            matches.sort(
                key=lambda m: os.path.getmtime(
                    os.path.join(cwd, m.rstrip("/"))
                ) if os.path.exists(os.path.join(cwd, m.rstrip("/"))) else 0,
                reverse=True,
            )
        except OSError:
            pass

        header = f"{len(matches)} archivos"
        if len(matches) >= MAX_SEARCH_RESULTS:
            header += f" (limitado a {MAX_SEARCH_RESULTS})"

        return f"{header}:\n" + "\n".join(matches)

    async def _search_code(self, inp: Dict[str, Any]) -> str:
        """Search for a pattern in code files using ripgrep or fallback."""
        query = inp.get("pattern", inp.get("query", ""))
        path = inp.get("path", inp.get("directory", "."))
        file_pattern = inp.get("file_pattern", inp.get("glob", ""))
        case_insensitive = inp.get("case_insensitive", not inp.get("case_sensitive", True))
        output_mode = inp.get("output_mode", "content")
        head_limit = int(inp.get("head_limit", 50))
        offset = int(inp.get("offset", 0))
        context_lines = inp.get("context_lines", 3)

        if not query:
            raise ValueError("Se requiere el parametro 'query' o 'pattern'")

        ok, result = self._validator.validate_read(path)
        if not ok:
            raise ToolDeniedError(result)
        resolved = result

        rg_path = shutil.which("rg")
        if rg_path:
            return await self._search_with_ripgrep_v2(
                rg_path, query, resolved, file_pattern, case_insensitive,
                output_mode, head_limit, offset, context_lines,
            )
        return self._search_with_python(
            query, resolved, file_pattern, not case_insensitive
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
            "--no-binary",
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
            output = stdout.decode("utf-8", errors="replace").replace("\x00", "")

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

    async def _search_with_ripgrep_v2(
        self,
        rg_path: str,
        query: str,
        directory: str,
        file_pattern: str,
        case_insensitive: bool,
        output_mode: str,
        head_limit: int,
        offset: int,
        context_lines: int,
    ) -> str:
        """Run ripgrep with full output mode support."""
        cmd = [rg_path, "--no-heading", "--no-binary", "--max-columns", "500"]

        if case_insensitive:
            cmd.append("--ignore-case")

        if output_mode == "files_with_matches":
            cmd.append("--files-with-matches")
            cmd.extend(["--sort", "modified"])
        elif output_mode == "count":
            cmd.append("--count")
        else:
            cmd.append("--line-number")
            if context_lines:
                cmd.extend(["-C", str(context_lines)])

        if file_pattern:
            cmd.extend(["--glob", file_pattern])

        cmd.extend([query, directory])

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=15)
            output = stdout.decode("utf-8", errors="replace").replace("\x00", "")

            if not output.strip():
                return f'No se encontraron resultados para "{query}"'

            cwd = self._validator.working_dir
            lines = output.strip().split("\n")

            # Make paths relative
            relative_lines = []
            for line in lines:
                if directory in line:
                    line = line.replace(directory, os.path.relpath(directory, cwd), 1)
                relative_lines.append(line)

            # Apply offset and limit
            if offset > 0:
                relative_lines = relative_lines[offset:]
            if head_limit > 0:
                relative_lines = relative_lines[:head_limit]

            return "\n".join(relative_lines)

        except asyncio.TimeoutError:
            return "Busqueda cancelada: timeout de 15 segundos"
        except Exception:
            return self._search_with_python(query, directory, file_pattern, not case_insensitive)

    async def _grep(self, inp: Dict[str, Any]) -> str:
        """Powerful grep tool with ripgrep — multiline, file type filter, all output modes."""
        pattern = inp.get("pattern", "")
        if not pattern:
            raise ValueError("Se requiere el parametro 'pattern'")

        path = inp.get("path", ".")
        ok, result = self._validator.validate_read(path)
        if not ok:
            raise ToolDeniedError(result)
        resolved = result

        glob_filter = inp.get("glob", "")
        file_type = inp.get("file_type", "")
        output_mode = inp.get("output_mode", "files_with_matches")
        case_insensitive = inp.get("case_insensitive", False)
        multiline = inp.get("multiline", False)
        head_limit = int(inp.get("head_limit", 50))
        offset = int(inp.get("offset", 0))
        context_before = inp.get("context_before", 0)
        context_after = inp.get("context_after", 0)

        rg_path = shutil.which("rg")
        if not rg_path:
            return await self._search_code({"query": pattern, "path": path, "output_mode": output_mode})

        cmd = [rg_path, "--no-heading", "--no-binary", "--max-columns", "500"]

        if case_insensitive:
            cmd.append("--ignore-case")
        if multiline:
            cmd.extend(["-U", "--multiline-dotall"])
        if glob_filter:
            cmd.extend(["--glob", glob_filter])
        if file_type:
            cmd.extend(["--type", file_type])

        if output_mode == "files_with_matches":
            cmd.append("--files-with-matches")
            cmd.extend(["--sort", "modified"])
        elif output_mode == "count":
            cmd.append("--count")
        else:
            cmd.append("--line-number")
            if context_before:
                cmd.extend(["-B", str(context_before)])
            if context_after:
                cmd.extend(["-A", str(context_after)])

        cmd.extend([pattern, resolved])

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=15)
            output = stdout.decode("utf-8", errors="replace").replace("\x00", "")

            if not output.strip():
                return f'No se encontraron resultados para "{pattern}"'

            cwd = self._validator.working_dir
            lines = output.strip().split("\n")
            relative_lines = []
            for line in lines:
                if resolved in line:
                    line = line.replace(resolved, os.path.relpath(resolved, cwd), 1)
                relative_lines.append(line)

            if offset > 0:
                relative_lines = relative_lines[offset:]
            if head_limit > 0:
                relative_lines = relative_lines[:head_limit]

            return "\n".join(relative_lines)

        except asyncio.TimeoutError:
            return "Busqueda cancelada: timeout de 15 segundos"
        except Exception as exc:
            return f"Error en grep: {exc}"

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
                rel = os.path.relpath(resolved, self._validator.working_dir)
                title = f"Escribir {rel}"

                # Show diff against current content
                with open(resolved, "r", encoding="utf-8", errors="replace") as rf:
                    current_content = rf.read()
                detail = _build_write_diff(current_content, content)

                # Extra warning for sensitive files
                sensitive = self._validator.is_sensitive(resolved)
                if sensitive:
                    detail = f"[SENSIBLE: {sensitive}]\n{detail}"

            approved = await self._check_approval(title, detail)
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

        # Check that old_string exists (try exact match first, then normalized)
        count = current.count(old_string)
        if count == 0:
            # Try normalizing leading whitespace (tabs vs spaces)
            match_result = _fuzzy_find_and_replace(current, old_string, new_string)
            if match_result is not None:
                new_content = match_result
                count = 1
            else:
                raise ValueError(
                    f"old_string no encontrado en {path}. "
                    f"Verifica que el texto coincida exactamente."
                )
        else:
            # Apply replacement (all occurrences or just first)
            replace_all = inp.get("replace_all", False)
            if replace_all:
                new_content = current.replace(old_string, new_string)
            else:
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

            approved = await self._check_approval(title, detail)
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
        """Execute a shell command with timeout, streaming output to stderr."""
        import sys
        import time

        command = inp.get("command", "")
        timeout = min(
            int(inp.get("timeout", MAX_COMMAND_TIMEOUT)),
            MAX_COMMAND_TIMEOUT_HARD,
        )
        background = inp.get("background", False)
        description = inp.get("description", "")

        if not command:
            raise ValueError("Se requiere el parametro 'command'")

        # Check approval
        if self._request_approval:
            detail = f"$ {command}\n(timeout: {timeout}s)"

            # If the command runs a script file, show its content
            script_content = _extract_script_content(command)
            if script_content:
                detail += f"\n\n── contenido del script ──\n{script_content}"

            approved = await self._check_approval(
                f"Ejecutar comando",
                detail,
            )
            if not approved:
                raise ToolDeniedError("Operacion rechazada por el usuario")

        # Background execution
        if background:
            import uuid
            task_id = str(uuid.uuid4())[:8]
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=self._validator.working_dir,
            )
            desc = description or command[:50]
            return f"Comando ejecutandose en background (pid={proc.pid}, task_id={task_id}): {desc}"

        try:
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=self._validator.working_dir,
            )

            # Stream output in real-time while collecting it
            stdout_lines: List[str] = []
            stderr_lines: List[str] = []
            start_time = time.time()
            last_display = ""

            def _update_display(text: str) -> None:
                nonlocal last_display
                last_display = text
                elapsed = time.time() - start_time
                display = text
                if len(display) > 100:
                    display = display[:97] + "..."
                sys.stderr.write(
                    f"\r\033[K  \033[2m{display} ({elapsed:.0f}s)\033[0m"
                )
                sys.stderr.flush()

            async def _read_stream(
                stream: asyncio.StreamReader,
                collector: List[str],
            ) -> None:
                buf = ""
                while True:
                    try:
                        chunk = await asyncio.wait_for(stream.read(4096), timeout=2.0)
                    except asyncio.TimeoutError:
                        # No new output — update elapsed time on current display
                        _update_display(last_display or "Ejecutando...")
                        continue
                    if not chunk:
                        break
                    text = chunk.decode("utf-8", errors="replace")
                    buf += text
                    # Split into lines, keep incomplete last line in buffer
                    while "\n" in buf:
                        line, buf = buf.split("\n", 1)
                        line = line.rstrip("\r")
                        if line:
                            collector.append(line)
                            _update_display(line)
                # Flush remaining buffer
                if buf.strip():
                    collector.append(buf.strip())
                    _update_display(buf.strip())

            try:
                await asyncio.wait_for(
                    asyncio.gather(
                        _read_stream(proc.stdout, stdout_lines),
                        _read_stream(proc.stderr, stderr_lines),
                    ),
                    timeout=timeout,
                )
                await proc.wait()
            except asyncio.TimeoutError:
                try:
                    proc.kill()
                except ProcessLookupError:
                    pass
                # Clear streaming line
                sys.stderr.write("\r\033[K")
                sys.stderr.flush()
                partial = "\n".join(stdout_lines[-20:] + stderr_lines[-20:])
                return (
                    f"Comando cancelado: timeout de {timeout} segundos\n"
                    f"Ultimas lineas:\n{partial}"
                )

            # Clear streaming line
            sys.stderr.write("\r\033[K")
            sys.stderr.flush()

        except Exception as exc:
            raise RuntimeError(f"Error ejecutando comando: {exc}")

        output_parts: List[str] = []

        stdout_text = "\n".join(stdout_lines)
        stderr_text = "\n".join(stderr_lines)

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

    # ── New tools ─────────────────────────────────────────────────────

    async def _web_fetch(self, inp: Dict[str, Any]) -> str:
        """Fetch a URL and return content as text/markdown."""
        import httpx

        url = inp.get("url", "")
        if not url:
            raise ValueError("Se requiere el parametro 'url'")

        try:
            async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
                resp = await client.get(url, headers={"User-Agent": "gula-agent/1.0"})
                resp.raise_for_status()
                content_type = resp.headers.get("content-type", "")

                if "html" in content_type:
                    # Convert HTML to readable text
                    text = resp.text
                    # Strip HTML tags (simple approach)
                    text = re.sub(r'<script[^>]*>.*?</script>', '', text, flags=re.DOTALL)
                    text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.DOTALL)
                    text = re.sub(r'<[^>]+>', ' ', text)
                    text = re.sub(r'\s+', ' ', text).strip()
                    # Limit size
                    if len(text) > 15000:
                        text = text[:15000] + "\n... [truncado]"
                    return text
                else:
                    text = resp.text
                    if len(text) > 15000:
                        text = text[:15000] + "\n... [truncado]"
                    return text
        except Exception as exc:
            return f"Error fetching {url}: {exc}"

    async def _find_and_replace(self, inp: Dict[str, Any]) -> str:
        """Search and replace across multiple files."""
        search = inp.get("search", "")
        replace = inp.get("replace", "")
        file_pattern = inp.get("file_pattern", "")
        is_regex = inp.get("is_regex", False)

        if not search:
            raise ValueError("Se requiere el parametro 'search'")

        if is_regex:
            try:
                pattern = re.compile(search)
            except re.error as e:
                raise ValueError(f"Regex invalida: {e}")
        else:
            pattern = re.compile(re.escape(search))

        cwd = self._validator.working_dir
        changed_files = []

        for root, dirs, files in os.walk(cwd):
            dirs[:] = [d for d in dirs if not d.startswith(".")
                       and d not in ("node_modules", "__pycache__", "venv", ".venv", "build", "dist")]
            for name in files:
                if name.startswith("."):
                    continue
                if file_pattern and not fnmatch.fnmatch(name, file_pattern):
                    continue
                full = os.path.join(root, name)
                try:
                    with open(full, "r", encoding="utf-8", errors="replace") as f:
                        content = f.read()
                except (OSError, UnicodeDecodeError):
                    continue

                matches = list(pattern.finditer(content))
                if not matches:
                    continue

                # Apply replacement
                if is_regex:
                    new_content = pattern.sub(replace, content)
                else:
                    new_content = content.replace(search, replace)

                # Backup and write
                self._backup.create_backup(full)
                with open(full, "w", encoding="utf-8") as f:
                    f.write(new_content)

                rel = os.path.relpath(full, cwd)
                changed_files.append(f"{rel} ({len(matches)} reemplazos)")

        if not changed_files:
            return f'No se encontraron coincidencias para "{search}"'

        return f"{len(changed_files)} archivos modificados:\n" + "\n".join(changed_files)

    async def _file_diff(self, inp: Dict[str, Any]) -> str:
        """Show git diff for a file."""
        path = inp.get("path", "")
        commit = inp.get("commit", "HEAD")

        if not path:
            raise ValueError("Se requiere el parametro 'path'")

        ok, resolved = self._validator.validate_read(path)
        if not ok:
            raise ToolDeniedError(resolved)

        cmd = ["git", "diff", commit, "--", resolved]
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=self._validator.working_dir,
            )
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=10)
        except asyncio.TimeoutError:
            return "Timeout de 10 segundos"

        output = stdout.decode("utf-8", errors="replace")
        if not output.strip():
            return f"Sin cambios en {path} (comparando con {commit})"

        lines = output.split("\n")
        if len(lines) > MAX_OUTPUT_LINES:
            output = "\n".join(lines[:MAX_OUTPUT_LINES]) + "\n... [truncado]"

        return output

    async def _move_file(self, inp: Dict[str, Any]) -> str:
        """Move or rename a file/directory."""
        source = inp.get("source", "")
        destination = inp.get("destination", "")

        if not source or not destination:
            raise ValueError("Se requieren 'source' y 'destination'")

        ok, resolved_src = self._validator.validate_read(source)
        if not ok:
            raise ToolDeniedError(resolved_src)
        ok, resolved_dst = self._validator.validate_write(destination)
        if not ok:
            raise ToolDeniedError(resolved_dst)

        if not os.path.exists(resolved_src):
            raise FileNotFoundError(f"No encontrado: {source}")

        if self._request_approval:
            approved = await self._check_approval(
                f"Mover archivo",
                f"{source} → {destination}",
            )
            if not approved:
                raise ToolDeniedError("Operacion rechazada por el usuario")

        parent = os.path.dirname(resolved_dst)
        if parent:
            os.makedirs(parent, exist_ok=True)

        shutil.move(resolved_src, resolved_dst)
        return f"Movido: {source} → {destination}"

    async def _undo_edit(self, inp: Dict[str, Any]) -> str:
        """Undo the last edit by restoring from backup."""
        path = inp.get("path", "")
        if not path:
            raise ValueError("Se requiere el parametro 'path'")

        ok, resolved = self._validator.validate_write(path)
        if not ok:
            raise ToolDeniedError(resolved)

        # Find the most recent backup for this file
        index = self._backup._load_index()
        matching = [e for e in index if e["original_path"] == resolved]
        if not matching:
            return f"No hay backup disponible para {path}"

        latest = max(matching, key=lambda e: e["timestamp"])
        restored = self._backup.restore_backup(latest["backup_id"])
        if restored:
            rel = os.path.relpath(resolved, self._validator.working_dir)
            return f"Restaurado: {rel} (backup aplicado)"
        return f"Error al restaurar backup para {path}"

    async def _symbols(self, inp: Dict[str, Any]) -> str:
        """Extract symbol definitions from a file (LSP document_symbols equivalent)."""
        path = inp.get("path", "")
        if not path:
            raise ValueError("Se requiere el parametro 'path'")

        ok, resolved = self._validator.validate_read(path)
        if not ok:
            raise ToolDeniedError(resolved)

        if not os.path.isfile(resolved):
            raise FileNotFoundError(f"Archivo no encontrado: {path}")

        with open(resolved, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()

        ext = os.path.splitext(resolved)[1].lower()
        symbols = []

        # Language-aware symbol patterns
        patterns = {
            ".py": [
                (r'^(class\s+\w+)', "class"),
                (r'^(\s*def\s+\w+)', "function"),
                (r'^(\s*async\s+def\s+\w+)', "async function"),
            ],
            ".swift": [
                (r'^(\s*(?:class|struct|enum|protocol|actor)\s+\w+)', "type"),
                (r'^(\s*(?:func|init)\s+\w+)', "function"),
                (r'^(\s*(?:var|let)\s+\w+)', "property"),
                (r'^(\s*extension\s+\w+)', "extension"),
            ],
            ".kt": [
                (r'^(\s*(?:class|object|interface|data class|sealed class|enum class)\s+\w+)', "type"),
                (r'^(\s*(?:fun|suspend fun)\s+\w+)', "function"),
                (r'^(\s*(?:val|var)\s+\w+)', "property"),
            ],
            ".ts": [
                (r'^(\s*(?:class|interface|type|enum)\s+\w+)', "type"),
                (r'^(\s*(?:function|async function)\s+\w+)', "function"),
                (r'^(\s*(?:export\s+)?(?:const|let|var)\s+\w+)', "variable"),
            ],
            ".js": [
                (r'^(\s*class\s+\w+)', "class"),
                (r'^(\s*(?:function|async function)\s+\w+)', "function"),
                (r'^(\s*(?:const|let|var)\s+\w+\s*=\s*(?:function|\(|async))', "function"),
            ],
            ".dart": [
                (r'^(\s*(?:class|mixin|extension|enum)\s+\w+)', "type"),
                (r'^(\s*\w+\s+\w+\s*\()', "function"),
            ],
            ".go": [
                (r'^(type\s+\w+\s+(?:struct|interface))', "type"),
                (r'^(func\s+(?:\(\w+\s+\*?\w+\)\s+)?\w+)', "function"),
            ],
        }

        file_patterns = patterns.get(ext, patterns.get(".py", []))

        for i, line in enumerate(lines, 1):
            for regex, kind in file_patterns:
                m = re.match(regex, line)
                if m:
                    symbols.append(f"{i:>5} [{kind}] {m.group(1).strip()}")
                    break

        if not symbols:
            return f"No se encontraron simbolos en {path}"

        return f"{len(symbols)} simbolos en {path}:\n" + "\n".join(symbols)

    async def _find_definition(self, inp: Dict[str, Any]) -> str:
        """Find where a symbol is defined in the project (LSP go_to_definition)."""
        symbol = inp.get("symbol", "")
        file_pattern = inp.get("file_pattern", "")

        if not symbol:
            raise ValueError("Se requiere el parametro 'symbol'")

        # Build regex patterns for common definition forms across languages
        def_patterns = [
            rf'^\s*(?:class|struct|enum|protocol|interface|actor|type)\s+{re.escape(symbol)}\b',
            rf'^\s*(?:def|func|fun|function|suspend fun|async def)\s+{re.escape(symbol)}\b',
            rf'^\s*(?:val|var|let|const)\s+{re.escape(symbol)}\b',
            rf'^\s*extension\s+{re.escape(symbol)}\b',
            rf'^\s*data\s+class\s+{re.escape(symbol)}\b',
        ]
        combined = "|".join(f"({p})" for p in def_patterns)

        # Use grep to search
        return await self._grep({
            "pattern": combined,
            "output_mode": "content",
            "glob": file_pattern or None,
            "head_limit": 20,
            "context_after": 3,
        })

    async def _find_references(self, inp: Dict[str, Any]) -> str:
        """Find all references to a symbol in the project (LSP find_references)."""
        symbol = inp.get("symbol", "")
        file_pattern = inp.get("file_pattern", "")

        if not symbol:
            raise ValueError("Se requiere el parametro 'symbol'")

        return await self._grep({
            "pattern": rf'\b{re.escape(symbol)}\b',
            "output_mode": "content",
            "glob": file_pattern or None,
            "head_limit": 50,
        })

    # ── Directory access ────────────────────────────────────────────────

    async def _request_dir_access(self, exc: OutsideAllowedDirError) -> bool:
        """Ask the user for permission to access a directory outside the project.

        If the user approves, the directory is added to the validator's
        allow-list so subsequent accesses succeed without prompting again.
        """
        if not self._request_approval:
            return False

        approved = await self._check_approval(
            f"Acceder a {exc.requested_dir}",
            (
                f"El agente quiere acceder a '{exc.raw_path}' que esta fuera\n"
                f"del directorio de trabajo actual ({exc.working_dir}).\n\n"
                f"Se permitira acceso a: {exc.requested_dir}"
            ),
        )
        if approved:
            self._validator.add_allowed_dir(exc.requested_dir)
        return approved

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


def _adapt_indentation(
    original_lines: List[str],
    old_lines: List[str],
    new_lines: List[str],
) -> str:
    """Adapt new_lines indentation to match original file style.

    Detects whether the original file uses tabs or spaces and converts
    the new_string accordingly, preserving relative indentation.
    """
    if not original_lines or not old_lines or not new_lines:
        return "\n".join(new_lines)

    # Detect if the original uses tabs by checking all non-empty lines
    uses_tabs = any(line.startswith("\t") for line in original_lines if line.strip())

    if uses_tabs:
        # Original file uses tabs — convert spaces in new_string to tabs
        # First, figure out how many spaces = 1 tab by looking at old_string
        # (the LLM-sent version, which uses spaces instead of tabs)
        old_first = next((l for l in old_lines if l.strip()), "")
        orig_first = next((l for l in original_lines if l.strip()), "")

        # Count tabs in original vs spaces in old
        orig_tabs = len(orig_first) - len(orig_first.lstrip("\t"))
        old_spaces = len(old_first) - len(old_first.lstrip(" "))

        if orig_tabs > 0 and old_spaces > 0:
            spaces_per_tab = old_spaces // orig_tabs
        else:
            spaces_per_tab = 4  # sensible default

        adapted = []
        for line in new_lines:
            if not line.strip():
                adapted.append(line)
                continue
            # Count leading spaces and convert to tabs
            stripped = line.lstrip(" ")
            num_spaces = len(line) - len(stripped)
            num_tabs = num_spaces // spaces_per_tab
            remainder = num_spaces % spaces_per_tab
            adapted.append("\t" * num_tabs + " " * remainder + stripped)
        return "\n".join(adapted)

    # Original uses spaces — just adjust indent level difference
    orig_first = next((l for l in original_lines if l.strip()), "")
    old_first = next((l for l in old_lines if l.strip()), "")

    orig_indent = len(orig_first) - len(orig_first.lstrip())
    old_indent = len(old_first) - len(old_first.lstrip())
    indent_diff = orig_indent - old_indent

    if indent_diff == 0:
        return "\n".join(new_lines)

    adapted = []
    for line in new_lines:
        if not line.strip():
            adapted.append(line)
        elif indent_diff > 0:
            adapted.append(" " * indent_diff + line)
        else:
            remove = abs(indent_diff)
            if line[:remove].strip() == "":
                adapted.append(line[remove:])
            else:
                adapted.append(line)
    return "\n".join(adapted)


def _fuzzy_find_and_replace(
    content: str, old_string: str, new_string: str
) -> Optional[str]:
    """Try to find old_string with normalized whitespace and apply replacement.

    Handles common LLM mistakes:
      - Tabs vs spaces mismatch
      - Trailing whitespace differences
      - Leading whitespace differences on each line
    """
    import re

    # Strategy 1: Normalize tabs/spaces in both and find the match
    def normalize_indent(text: str) -> str:
        lines = text.split("\n")
        return "\n".join(line.expandtabs(4) for line in lines)

    norm_content = normalize_indent(content)
    norm_old = normalize_indent(old_string)

    if norm_content.count(norm_old) == 1:
        # Find the position in normalized content
        pos = norm_content.find(norm_old)
        # Map back to original: find the corresponding lines
        norm_before = norm_content[:pos]
        start_line = norm_before.count("\n")
        old_line_count = old_string.count("\n") + 1

        content_lines = content.split("\n")
        original_old_lines = content_lines[start_line:start_line + old_line_count]
        original_old = "\n".join(original_old_lines)

        # Adapt new_string indentation to match the original file style
        new_string = _adapt_indentation(
            original_old_lines, old_string.split("\n"), new_string.split("\n")
        )

        return content.replace(original_old, new_string, 1)

    # Strategy 2: Strip trailing whitespace on each line
    def strip_trailing(text: str) -> str:
        return "\n".join(line.rstrip() for line in text.split("\n"))

    stripped_content = strip_trailing(content)
    stripped_old = strip_trailing(old_string)

    if stripped_content.count(stripped_old) == 1:
        # Find matching lines in original
        pos = stripped_content.find(stripped_old)
        before = stripped_content[:pos]
        start_line = before.count("\n")
        old_line_count = old_string.count("\n") + 1

        content_lines = content.split("\n")
        original_old = "\n".join(content_lines[start_line:start_line + old_line_count])
        return content.replace(original_old, new_string, 1)

    return None


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


def _extract_script_content(command: str) -> Optional[str]:
    """Extract and return the content of a script file referenced in a command.

    Detects patterns like:
      python3 /tmp/fix.py, ruby script.rb, bash ./deploy.sh,
      sh -c 'cat script.sh', node fix.js, etc.

    Returns the script content (truncated) or None if no script detected.
    """
    import shlex

    # Common interpreters and script extensions
    _INTERPRETERS = {
        "python", "python3", "ruby", "bash", "sh", "zsh",
        "node", "perl", "swift",
    }
    _SCRIPT_EXTENSIONS = {
        ".py", ".rb", ".sh", ".js", ".pl", ".swift", ".bash", ".zsh",
    }

    try:
        parts = shlex.split(command)
    except ValueError:
        parts = command.split()

    if not parts:
        return None

    # Find a file argument that looks like a script
    script_path = None
    for i, part in enumerate(parts):
        # Skip flags
        if part.startswith("-"):
            continue
        # Check if it's an interpreter followed by a file
        base = os.path.basename(part)
        if base in _INTERPRETERS and i + 1 < len(parts):
            candidate = parts[i + 1]
            if not candidate.startswith("-") and os.path.isfile(candidate):
                script_path = candidate
                break
            continue
        # Check if the part itself is a script file
        _, ext = os.path.splitext(part)
        if ext in _SCRIPT_EXTENSIONS and os.path.isfile(part):
            script_path = part
            break

    if not script_path:
        return None

    try:
        with open(script_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        # Truncate long scripts
        lines = content.split("\n")
        if len(lines) > 60:
            content = "\n".join(lines[:60])
            content += f"\n... ({len(lines)} lineas totales)"
        return content
    except OSError:
        return None


def _build_write_diff(current: str, new: str) -> str:
    """Build a unified-style diff for write_file overwrite approval.

    Uses difflib to show only the changed lines with context,
    so the user can see exactly what changes before approving.
    """
    import difflib

    current_lines = current.splitlines(keepends=True)
    new_lines = new.splitlines(keepends=True)

    diff = list(difflib.unified_diff(
        current_lines, new_lines,
        fromfile="actual", tofile="nuevo",
        lineterm="",
    ))

    if not diff:
        return "Sin cambios (contenido identico)"

    parts: List[str] = []
    for line in diff:
        line = line.rstrip("\n")
        if line.startswith("---") or line.startswith("+++"):
            continue  # skip file headers
        elif line.startswith("@@"):
            parts.append(f"  {line}")
        elif line.startswith("-"):
            parts.append(f"  - {line[1:]}")
        elif line.startswith("+"):
            parts.append(f"  + {line[1:]}")
        else:
            parts.append(f"    {line[1:]}" if line.startswith(" ") else f"    {line}")

    # Limit display
    if len(parts) > 40:
        parts = parts[:40]
        parts.append("  ... (truncado)")

    return "\n".join(parts)
