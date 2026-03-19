"""HTTPX-based implementation of the API client port."""

from __future__ import annotations

import asyncio
import json
from typing import Any, AsyncGenerator, Dict, List, Optional

import httpx

from ...application.ports.driven.api_client_port import ApiClientPort
from ...domain.entities.config import AuthTokens
from ...domain.entities.sse_event import SSEEvent, ErrorEvent
from .sse_parser import parse_sse_line, parse_sse_event, parse_raw_error


class HttpxApiClient(ApiClientPort):
    """API client using httpx for async HTTP with SSE streaming.

    Features:
      - Async streaming for real-time SSE event delivery.
      - Retry with exponential backoff (3 attempts) for transient errors.
      - Proper SSE line parsing and domain event mapping.
    """

    MAX_RETRIES = 3
    BASE_BACKOFF = 1.0  # seconds
    CONNECT_TIMEOUT = 30.0
    READ_TIMEOUT = 300.0  # 5 minutes for long-running agent turns

    def __init__(self, debug: bool = False) -> None:
        self._debug = debug

    async def send_chat(
        self,
        endpoint: str,
        access_token: str,
        payload: Dict[str, Any],
    ) -> AsyncGenerator[SSEEvent, None]:
        """Stream SSE events from the chat endpoint."""
        last_error: Optional[Exception] = None

        for attempt in range(self.MAX_RETRIES):
            try:
                async for event in self._do_stream(endpoint, access_token, payload):
                    yield event
                return  # Success — all events yielded
            except (httpx.ConnectError, httpx.ReadTimeout, httpx.ConnectTimeout) as exc:
                last_error = exc
                if attempt < self.MAX_RETRIES - 1:
                    wait = self.BASE_BACKOFF * (2 ** attempt)
                    if self._debug:
                        import sys
                        print(
                            f"[DEBUG] Retry {attempt + 1}/{self.MAX_RETRIES} "
                            f"after {wait}s: {exc}",
                            file=sys.stderr,
                        )
                    await asyncio.sleep(wait)
            except httpx.HTTPStatusError as exc:
                # Don't retry HTTP errors like 401, 403, 500
                yield ErrorEvent(
                    error=f"HTTP {exc.response.status_code}: {exc.response.text[:200]}"
                )
                return

        # All retries exhausted
        yield ErrorEvent(
            error=f"No se pudo conectar al servidor despues de {self.MAX_RETRIES} intentos: {last_error}"
        )

    async def _do_stream(
        self,
        endpoint: str,
        access_token: str,
        payload: Dict[str, Any],
    ) -> AsyncGenerator[SSEEvent, None]:
        """Perform a single streaming request and yield SSE events."""
        timeout = httpx.Timeout(
            connect=self.CONNECT_TIMEOUT,
            read=self.READ_TIMEOUT,
            write=30.0,
            pool=30.0,
        )

        async with httpx.AsyncClient(timeout=timeout) as client:
            async with client.stream(
                "POST",
                endpoint,
                json=payload,
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/json",
                    "Accept": "text/event-stream",
                },
            ) as response:
                # Check for HTTP errors before streaming
                if response.status_code != 200:
                    body = ""
                    async for chunk in response.aiter_text():
                        body += chunk
                        if len(body) > 1000:
                            break
                    error_event = parse_raw_error(body.strip())
                    if error_event:
                        # Prefix with HTTP status for retry logic
                        error_event = ErrorEvent(
                            error=f"HTTP {response.status_code}: {error_event.error}"
                        )
                        yield error_event
                    else:
                        yield ErrorEvent(
                            error=f"HTTP {response.status_code}: {body[:200]}"
                        )
                    return

                # Stream SSE lines
                current_event_type: Optional[str] = None
                first_line = True

                async for raw_line in response.aiter_lines():
                    line = raw_line.strip()
                    if not line:
                        # Empty line = event boundary in SSE
                        current_event_type = None
                        continue

                    field, value = parse_sse_line(line)

                    if field == "event":
                        current_event_type = value

                    elif field == "data" and current_event_type and value:
                        event = parse_sse_event(current_event_type, value)
                        if event is not None:
                            yield event

                    elif field == "raw" and first_line and value:
                        # Possibly a JSON error response without SSE framing
                        error_event = parse_raw_error(value)
                        if error_event:
                            yield error_event
                            return

                    first_line = False

    async def refresh_token(
        self,
        api_url: str,
        refresh_token: str,
    ) -> AuthTokens:
        """Exchange refresh token for new token pair."""
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{api_url}/users/refresh",
                json={"refresh_token": refresh_token},
            )
            response.raise_for_status()
            data = response.json()
            return AuthTokens(
                access_token=data["access_token"],
                refresh_token=data["refresh_token"],
            )

    async def get_quota(
        self,
        api_url: str,
        access_token: str,
    ) -> Dict[str, Any]:
        """Fetch user quota information."""
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                f"{api_url}/users/me/quota",
                headers={"Authorization": f"Bearer {access_token}"},
            )
            response.raise_for_status()
            return response.json()

    async def get_models(
        self,
        api_url: str,
        access_token: str,
    ) -> List[Dict[str, Any]]:
        """Fetch available models."""
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                f"{api_url}/agent/models",
                headers={"Authorization": f"Bearer {access_token}"},
            )
            response.raise_for_status()
            return response.json()

    async def get_conversations(
        self,
        api_url: str,
        access_token: str,
    ) -> List[Dict[str, Any]]:
        """Fetch conversation history."""
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                f"{api_url}/agent/conversations",
                headers={"Authorization": f"Bearer {access_token}"},
            )
            response.raise_for_status()
            return response.json()

    async def get_subagents(
        self,
        api_url: str,
        access_token: str,
    ) -> Dict[str, Any]:
        """Fetch available subagents."""
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                f"{api_url}/agent/subagents",
                headers={"Authorization": f"Bearer {access_token}"},
            )
            response.raise_for_status()
            return response.json()
