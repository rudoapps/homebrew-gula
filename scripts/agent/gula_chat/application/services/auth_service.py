"""Authentication service — ensures valid tokens before API calls."""

from __future__ import annotations

from ..ports.driven.api_client_port import ApiClientPort
from ..ports.driven.config_port import ConfigPort
from ...domain.entities.config import AppConfig


class AuthenticationError(Exception):
    """Raised when authentication fails and cannot be recovered."""


class AuthService:
    """Manages authentication tokens.

    Responsibilities:
      - Check if the current access token is present.
      - Refresh expired tokens using the refresh token.
      - Persist updated tokens to config.
    """

    def __init__(
        self,
        config_port: ConfigPort,
        api_client: ApiClientPort,
    ) -> None:
        self._config_port = config_port
        self._api_client = api_client

    def get_config(self) -> AppConfig:
        """Return the current config (re-reads from disk)."""
        return self._config_port.get_config()

    async def ensure_valid_token(self) -> AppConfig:
        """Ensure we have a valid access token, refreshing if needed.

        Returns:
            An AppConfig with a (presumably) valid access_token.

        Raises:
            AuthenticationError: If no tokens are available or refresh fails.
        """
        config = self._config_port.get_config()

        if not config.refresh_token:
            raise AuthenticationError(
                "No estas autenticado. Ejecuta 'gula agent login' primero."
            )

        if not config.access_token:
            # No access token but we have a refresh token — try refreshing
            return await self._do_refresh(config)

        return config

    async def refresh(self) -> AppConfig:
        """Force-refresh the access token.

        Returns:
            Updated AppConfig with fresh tokens.

        Raises:
            AuthenticationError: If the refresh token is invalid.
        """
        config = self._config_port.get_config()
        if not config.refresh_token:
            raise AuthenticationError(
                "No hay refresh token. Ejecuta 'gula agent login' primero."
            )
        return await self._do_refresh(config)

    async def _do_refresh(self, config: AppConfig) -> AppConfig:
        """Perform the actual token refresh."""
        try:
            tokens = await self._api_client.refresh_token(
                api_url=config.api_url,
                refresh_token=config.refresh_token,  # type: ignore[arg-type]
            )
            self._config_port.set_config("access_token", tokens.access_token)
            self._config_port.set_config("refresh_token", tokens.refresh_token)
            return self._config_port.get_config()
        except Exception as exc:
            raise AuthenticationError(
                f"No se pudo renovar el token: {exc}"
            ) from exc
