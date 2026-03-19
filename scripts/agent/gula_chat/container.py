"""Composition root — wires all dependencies together."""

from __future__ import annotations

from .application.ports.driven.api_client_port import ApiClientPort
from .application.ports.driven.clipboard_port import ClipboardPort
from .application.ports.driven.config_port import ConfigPort
from .application.services.auth_service import AuthService
from .application.services.chat_service import ChatService
from .driven.api.httpx_client import HttpxApiClient
from .driven.clipboard.macos_clipboard_adapter import MacOSClipboardAdapter
from .driven.config.json_config_adapter import JsonConfigAdapter


class Container:
    """Dependency injection container.

    Creates and wires all layers following the dependency rule:
      domain <- application <- driven (infrastructure)
                            <- driving (CLI/UI)

    All driven adapters are created here and injected into application services.
    The driving layer receives services from this container.
    """

    def __init__(self, debug: bool = False) -> None:
        # ── Driven adapters (infrastructure) ────────────────────────────
        self._config_adapter = JsonConfigAdapter()
        self._api_client = HttpxApiClient(debug=debug)
        self._clipboard_adapter = MacOSClipboardAdapter()

        # ── Application services ────────────────────────────────────────
        self._auth_service = AuthService(
            config_port=self._config_adapter,
            api_client=self._api_client,
        )
        self._chat_service = ChatService(
            auth_service=self._auth_service,
            api_client=self._api_client,
            config_port=self._config_adapter,
        )

    # ── Public accessors for the driving layer ──────────────────────────

    @property
    def config_port(self) -> ConfigPort:
        return self._config_adapter

    @property
    def clipboard_port(self) -> ClipboardPort:
        return self._clipboard_adapter

    @property
    def api_client(self) -> ApiClientPort:
        return self._api_client

    @property
    def auth_service(self) -> AuthService:
        return self._auth_service

    @property
    def chat_service(self) -> ChatService:
        return self._chat_service
