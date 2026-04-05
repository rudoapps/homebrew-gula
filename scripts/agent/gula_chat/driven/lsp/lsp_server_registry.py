"""Registry mapping project types to LSP server commands with auto-install."""

from __future__ import annotations

import logging
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class LSPServerConfig:
    """Configuration for an LSP server."""
    command: List[str]
    install_cmd: Optional[str] = None  # pip/npm/brew command to install
    fallback: Optional[List[str]] = None
    fallback_install_cmd: Optional[str] = None


_LSP_SERVERS: Dict[str, LSPServerConfig] = {
    "python": LSPServerConfig(
        command=["pyright-langserver", "--stdio"],
        install_cmd="pip3 install pyright",
        fallback=["pylsp"],
        fallback_install_cmd="pip3 install python-lsp-server",
    ),
    "python/django": LSPServerConfig(
        command=["pyright-langserver", "--stdio"],
        install_cmd="pip3 install pyright",
        fallback=["pylsp"],
        fallback_install_cmd="pip3 install python-lsp-server",
    ),
    "python/fastapi": LSPServerConfig(
        command=["pyright-langserver", "--stdio"],
        install_cmd="pip3 install pyright",
        fallback=["pylsp"],
        fallback_install_cmd="pip3 install python-lsp-server",
    ),
    "swift": LSPServerConfig(
        command=["sourcekit-lsp"],
        # sourcekit-lsp comes with Xcode
    ),
    "ios": LSPServerConfig(
        command=["sourcekit-lsp"],
    ),
    "kotlin": LSPServerConfig(
        command=["kotlin-language-server"],
        install_cmd="brew install kotlin-language-server",
    ),
    "android": LSPServerConfig(
        command=["kotlin-language-server"],
        install_cmd="brew install kotlin-language-server",
    ),
    "node": LSPServerConfig(
        command=["typescript-language-server", "--stdio"],
        install_cmd="npm install -g typescript-language-server typescript",
    ),
    "node/react": LSPServerConfig(
        command=["typescript-language-server", "--stdio"],
        install_cmd="npm install -g typescript-language-server typescript",
    ),
    "node/next": LSPServerConfig(
        command=["typescript-language-server", "--stdio"],
        install_cmd="npm install -g typescript-language-server typescript",
    ),
    "node/vue": LSPServerConfig(
        command=["typescript-language-server", "--stdio"],
        install_cmd="npm install -g typescript-language-server typescript",
    ),
    "node/express": LSPServerConfig(
        command=["typescript-language-server", "--stdio"],
        install_cmd="npm install -g typescript-language-server typescript",
    ),
    "dart": LSPServerConfig(
        command=["dart", "language-server", "--protocol=lsp"],
        # dart comes with Flutter/Dart SDK
    ),
    "flutter": LSPServerConfig(
        command=["dart", "language-server", "--protocol=lsp"],
    ),
    "go": LSPServerConfig(
        command=["gopls"],
        install_cmd="go install golang.org/x/tools/gopls@latest",
    ),
    "rust": LSPServerConfig(
        command=["rust-analyzer"],
        install_cmd="brew install rust-analyzer",
    ),
}


def detect_lsp_command(project_type: str) -> Optional[List[str]]:
    """Return the LSP server command for a project type, or None if unavailable."""
    config = _LSP_SERVERS.get(project_type)
    if not config:
        return None

    if shutil.which(config.command[0]):
        return list(config.command)

    if config.fallback and shutil.which(config.fallback[0]):
        return list(config.fallback)

    return None


def get_install_info(project_type: str) -> Optional[str]:
    """Get the install command for the LSP server of a project type."""
    config = _LSP_SERVERS.get(project_type)
    if not config:
        return None
    if shutil.which(config.command[0]):
        return None  # Already installed
    if config.fallback and shutil.which(config.fallback[0]):
        return None  # Fallback available
    return config.install_cmd or config.fallback_install_cmd


def auto_install_lsp(project_type: str) -> bool:
    """Attempt to install the LSP server for a project type.

    Returns True if installed successfully.
    """
    config = _LSP_SERVERS.get(project_type)
    if not config:
        return False

    # Already available
    if shutil.which(config.command[0]):
        return True
    if config.fallback and shutil.which(config.fallback[0]):
        return True

    # Try installing
    install_cmd = config.install_cmd or config.fallback_install_cmd
    if not install_cmd:
        return False

    logger.info("Auto-installing LSP server: %s", install_cmd)
    try:
        result = subprocess.run(
            install_cmd.split(),
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode == 0:
            logger.info("LSP server installed successfully")
            return True
        logger.warning("LSP install failed: %s", result.stderr[:200])
    except Exception as e:
        logger.warning("LSP install error: %s", e)

    return False
