"""Registry mapping project types to LSP server commands."""

from __future__ import annotations

import logging
import shutil
from dataclasses import dataclass
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class LSPServerConfig:
    """Configuration for an LSP server."""

    command: List[str]
    fallback: Optional[List[str]] = None


# Maps project_type (from ProjectContextBuilder.detect_project_type) to LSP servers.
# The first available command wins; fallback is tried if the primary is missing.
_LSP_SERVERS: Dict[str, LSPServerConfig] = {
    "python": LSPServerConfig(
        command=["pyright-langserver", "--stdio"],
        fallback=["pylsp"],
    ),
    "python/django": LSPServerConfig(
        command=["pyright-langserver", "--stdio"],
        fallback=["pylsp"],
    ),
    "python/fastapi": LSPServerConfig(
        command=["pyright-langserver", "--stdio"],
        fallback=["pylsp"],
    ),
    "swift": LSPServerConfig(
        command=["sourcekit-lsp"],
    ),
    "ios": LSPServerConfig(
        command=["sourcekit-lsp"],
    ),
    "kotlin": LSPServerConfig(
        command=["kotlin-language-server"],
    ),
    "android": LSPServerConfig(
        command=["kotlin-language-server"],
    ),
    "node": LSPServerConfig(
        command=["typescript-language-server", "--stdio"],
    ),
    "node/react": LSPServerConfig(
        command=["typescript-language-server", "--stdio"],
    ),
    "node/next": LSPServerConfig(
        command=["typescript-language-server", "--stdio"],
    ),
    "node/vue": LSPServerConfig(
        command=["typescript-language-server", "--stdio"],
    ),
    "node/express": LSPServerConfig(
        command=["typescript-language-server", "--stdio"],
    ),
    "dart": LSPServerConfig(
        command=["dart", "language-server", "--protocol=lsp"],
    ),
    "flutter": LSPServerConfig(
        command=["dart", "language-server", "--protocol=lsp"],
    ),
    "go": LSPServerConfig(
        command=["gopls"],
    ),
    "rust": LSPServerConfig(
        command=["rust-analyzer"],
    ),
}


def detect_lsp_command(project_type: str) -> Optional[List[str]]:
    """Return the LSP server command for a project type, or None if unavailable.

    Checks that the binary exists on PATH before returning.
    """
    config = _LSP_SERVERS.get(project_type)
    if not config:
        logger.debug("No LSP server configured for project type: %s", project_type)
        return None

    if shutil.which(config.command[0]):
        logger.debug("LSP server found: %s", config.command)
        return list(config.command)

    if config.fallback and shutil.which(config.fallback[0]):
        logger.debug("LSP fallback server found: %s", config.fallback)
        return list(config.fallback)

    logger.debug(
        "LSP server not found for %s (tried %s%s)",
        project_type,
        config.command[0],
        f", {config.fallback[0]}" if config.fallback else "",
    )
    return None
