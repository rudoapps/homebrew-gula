"""Authentication service — ensures valid tokens before API calls."""

from __future__ import annotations

import base64
import json
import time

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

        if not config.access_token or self._is_token_expired(config.access_token):
            # No access token or expired — refresh automatically
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

    @staticmethod
    def _is_token_expired(token: str, margin_seconds: int = 60) -> bool:
        """Check if a JWT is expired by decoding the payload (no verification).

        Args:
            token: The JWT access token.
            margin_seconds: Refresh this many seconds before actual expiry.

        Returns:
            True if the token is expired or will expire within margin_seconds.
        """
        try:
            parts = token.split(".")
            if len(parts) != 3:
                return True  # Not a valid JWT — treat as expired
            # Decode payload (base64url without padding)
            payload_b64 = parts[1]
            payload_b64 += "=" * (4 - len(payload_b64) % 4)  # pad
            payload = json.loads(base64.urlsafe_b64decode(payload_b64))
            exp = payload.get("exp")
            if exp is None:
                return False  # No expiry claim — assume valid
            return time.time() >= (exp - margin_seconds)
        except Exception:
            return True  # Can't parse — treat as expired

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
