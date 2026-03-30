"""Authentication service — ensures valid tokens before API calls."""

from __future__ import annotations

import asyncio
import base64
import json
import platform
import subprocess
import time
import webbrowser

from ..ports.driven.api_client_port import ApiClientPort
from ..ports.driven.config_port import ConfigPort
from ...domain.entities.config import AppConfig


class AuthenticationError(Exception):
    """Raised when authentication fails and cannot be recovered."""


class ServerUnavailableError(Exception):
    """Raised when the server is down (502, 503, timeout)."""


class AuthService:
    """Manages authentication tokens.

    Responsibilities:
      - Check if the current access token is present.
      - Refresh expired tokens using the refresh token.
      - Persist updated tokens to config.
      - Interactive browser-based login when no tokens exist.
    """

    LOGIN_POLL_INTERVAL = 2.0  # seconds
    LOGIN_MAX_ATTEMPTS = 60  # 2 minutes total

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

    async def login(self) -> AppConfig:
        """Perform interactive browser-based login.

        Creates a CLI auth session, opens the browser for the user to log in,
        then polls until the session completes or times out.

        Returns:
            Updated AppConfig with fresh tokens.

        Raises:
            AuthenticationError: If login fails or times out.
        """
        config = self._config_port.get_config()
        api_url = config.api_url

        # Step 1: Create auth session
        try:
            session_id = await self._api_client.create_auth_session(api_url)
        except Exception as exc:
            raise AuthenticationError(
                f"No se pudo crear la sesion de autenticacion: {exc}"
            ) from exc

        # Step 2: Open browser
        login_url = f"{api_url}/cli-auth/login?session={session_id}"
        self._open_browser(login_url)

        # Step 3: Poll for completion
        for _ in range(self.LOGIN_MAX_ATTEMPTS):
            await asyncio.sleep(self.LOGIN_POLL_INTERVAL)
            try:
                result = await self._api_client.poll_auth_session(
                    api_url, session_id
                )
            except Exception:
                continue  # Transient error — keep polling

            status = result.get("status", "")
            if status == "completed":
                access_token = result.get("access_token", "")
                refresh_token = result.get("refresh_token", "")
                user_email = result.get("user_email", "")
                if access_token and refresh_token:
                    self._config_port.set_config("access_token", access_token)
                    self._config_port.set_config("refresh_token", refresh_token)
                    if user_email:
                        self._config_port.set_config("user_email", user_email)
                    return self._config_port.get_config()
                raise AuthenticationError(
                    "El servidor no devolvio tokens validos."
                )
            elif status in ("expired", "not_found"):
                raise AuthenticationError(
                    "La sesion de autenticacion expiro. Intenta de nuevo."
                )
            # status == "pending" → keep polling

        raise AuthenticationError(
            "Tiempo de espera agotado. No se completo el login en el navegador."
        )

    @staticmethod
    def _open_browser(url: str) -> None:
        """Open URL in the default browser, cross-platform."""
        system = platform.system()
        try:
            if system == "Darwin":
                subprocess.Popen(["open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            elif system == "Linux":
                subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            elif system == "Windows":
                subprocess.Popen(["cmd", "/c", "start", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            else:
                webbrowser.open(url)
        except Exception:
            webbrowser.open(url)

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
        import httpx

        try:
            tokens = await self._api_client.refresh_token(
                api_url=config.api_url,
                refresh_token=config.refresh_token,  # type: ignore[arg-type]
            )
            self._config_port.set_config("access_token", tokens.access_token)
            self._config_port.set_config("refresh_token", tokens.refresh_token)
            return self._config_port.get_config()
        except (httpx.ConnectError, httpx.ConnectTimeout, httpx.ReadTimeout) as exc:
            raise ServerUnavailableError(
                "No se puede conectar al servidor. Verifica tu conexion."
            ) from exc
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code in (502, 503, 504):
                raise ServerUnavailableError(
                    f"El servidor no esta disponible ({exc.response.status_code})."
                ) from exc
            raise AuthenticationError(
                f"No se pudo renovar el token: {exc}"
            ) from exc
        except Exception as exc:
            raise AuthenticationError(
                f"No se pudo renovar el token: {exc}"
            ) from exc
