"""Code analysis tools: symbols, find_definition, find_references."""

from __future__ import annotations

import os
import re
from typing import Any, Dict

from .base import BaseToolExecutor, ToolDeniedError

# Language-specific symbol patterns
SYMBOL_PATTERNS = {
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


class CodeAnalysisToolExecutor(BaseToolExecutor):
    """Handles code intelligence operations (LSP-like)."""

    async def symbols(self, inp: Dict[str, Any]) -> str:
        """Extract symbol definitions from a file."""
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
        file_patterns = SYMBOL_PATTERNS.get(ext, SYMBOL_PATTERNS.get(".py", []))

        symbols = []
        for i, line in enumerate(lines, 1):
            for regex, kind in file_patterns:
                m = re.match(regex, line)
                if m:
                    symbols.append(f"{i:>5} [{kind}] {m.group(1).strip()}")
                    break

        if not symbols:
            return f"No se encontraron simbolos en {path}"

        return f"{len(symbols)} simbolos en {path}:\n" + "\n".join(symbols)

    async def find_definition(self, inp: Dict[str, Any]) -> str:
        """Find where a symbol is defined in the project."""
        symbol = inp.get("symbol", "")
        file_pattern = inp.get("file_pattern", "")

        if not symbol:
            raise ValueError("Se requiere el parametro 'symbol'")

        def_patterns = [
            rf'^\s*(?:class|struct|enum|protocol|interface|actor|type)\s+{re.escape(symbol)}\b',
            rf'^\s*(?:def|func|fun|function|suspend fun|async def)\s+{re.escape(symbol)}\b',
            rf'^\s*(?:val|var|let|const)\s+{re.escape(symbol)}\b',
            rf'^\s*extension\s+{re.escape(symbol)}\b',
            rf'^\s*data\s+class\s+{re.escape(symbol)}\b',
        ]
        combined = "|".join(f"({p})" for p in def_patterns)

        # Delegate to grep
        from .search_tools import SearchToolExecutor
        search = SearchToolExecutor(self._validator, self._backup, self._request_approval)
        search.set_permission_mode(self._permission_mode)
        return await search.grep({
            "pattern": combined,
            "output_mode": "content",
            "glob": file_pattern or None,
            "head_limit": 20,
            "context_after": 3,
        })

    async def find_references(self, inp: Dict[str, Any]) -> str:
        """Find all references to a symbol in the project."""
        symbol = inp.get("symbol", "")
        file_pattern = inp.get("file_pattern", "")

        if not symbol:
            raise ValueError("Se requiere el parametro 'symbol'")

        from .search_tools import SearchToolExecutor
        search = SearchToolExecutor(self._validator, self._backup, self._request_approval)
        search.set_permission_mode(self._permission_mode)
        return await search.grep({
            "pattern": rf'\b{re.escape(symbol)}\b',
            "output_mode": "content",
            "glob": file_pattern or None,
            "head_limit": 50,
        })
