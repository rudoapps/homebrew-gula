"""SSE event renderer — maps domain events to Rich console output."""

from __future__ import annotations

import time
from typing import List, Optional

from ...domain.entities.sse_event import (
    SSEEvent,
    StartedEvent,
    ThinkingEvent,
    TextEvent,
    ToolRequestsEvent,
    CompleteEvent,
    ErrorEvent,
    CostWarningEvent,
    CostLimitExceededEvent,
    RateLimitedEvent,
    RagSearchEvent,
    RagContextEvent,
    DelegationEvent,
    ProviderFallbackEvent,
    NoProvidersAvailableEvent,
    RepairedEvent,
)
from .console import get_console
from .markdown import render_markdown
from .spinner import Spinner


class SSERenderer:
    """Renders SSE events to the terminal using Rich.

    Manages the lifecycle of spinners, streaming text, headers, and
    summary panels to produce output matching the gula agent UX.
    """

    def __init__(self) -> None:
        self._console = get_console()
        self._spinner = Spinner()
        self._start_time: float = time.time()

        # Text accumulation for streaming
        self._text_chunks: List[str] = []
        self._streaming: bool = False
        self._header_shown: bool = False

        # Metadata from started event
        self._model: str = ""
        self._rag_indicator: str = ""
        self._conversation_id: Optional[int] = None

    def render(self, event: SSEEvent) -> None:
        """Render a single SSE event to the console.

        Args:
            event: A typed SSE event from the domain layer.
        """
        if isinstance(event, StartedEvent):
            self._handle_started(event)
        elif isinstance(event, ThinkingEvent):
            self._handle_thinking(event)
        elif isinstance(event, TextEvent):
            self._handle_text(event)
        elif isinstance(event, ToolRequestsEvent):
            self._handle_tool_requests(event)
        elif isinstance(event, CompleteEvent):
            self._handle_complete(event)
        elif isinstance(event, ErrorEvent):
            self._handle_error(event)
        elif isinstance(event, CostWarningEvent):
            self._handle_cost_warning(event)
        elif isinstance(event, CostLimitExceededEvent):
            self._handle_cost_limit(event)
        elif isinstance(event, RateLimitedEvent):
            self._handle_rate_limited(event)
        elif isinstance(event, RagSearchEvent):
            self._handle_rag_search(event)
        elif isinstance(event, RagContextEvent):
            self._handle_rag_context(event)
        elif isinstance(event, DelegationEvent):
            self._handle_delegation(event)
        elif isinstance(event, ProviderFallbackEvent):
            self._handle_provider_fallback(event)
        elif isinstance(event, NoProvidersAvailableEvent):
            self._handle_no_providers(event)
        elif isinstance(event, RepairedEvent):
            self._handle_repaired(event)

    def finalize(self) -> None:
        """Clean up any remaining state (flush text, stop spinner)."""
        self._flush_remaining_text()
        self._spinner.stop()

    def show_waiting_spinner(self, message: str = "Procesando...") -> None:
        """Show a spinner while waiting for the server response."""
        self._spinner.start(message)

    # ── Event handlers ──────────────────────────────────────────────────

    def _handle_started(self, event: StartedEvent) -> None:
        self._conversation_id = event.conversation_id
        self._model = event.model
        self._start_time = time.time()

        # Build RAG indicator
        if event.rag_enabled and event.rag_info:
            scope = event.rag_info.get("scope", "current")
            chunks = event.rag_info.get("chunks", 0)
            if scope == "related":
                self._rag_indicator = f" [agent.rag_multi]\\[RAG:{chunks} multi-proyecto][/agent.rag_multi]"
            else:
                self._rag_indicator = f" [agent.rag]\\[RAG:{chunks}][/agent.rag]"
        elif event.rag_enabled:
            self._rag_indicator = " [agent.rag]\\[RAG][/agent.rag]"

        model_tag = f" [agent.model]({event.model})[/agent.model]" if event.model else ""
        self._spinner.start(f"Conversacion #{event.conversation_id}{self._rag_indicator}{model_tag}")

    def _handle_thinking(self, event: ThinkingEvent) -> None:
        model_tag = f" [agent.model]({event.model})[/agent.model]" if event.model else ""
        self._spinner.update(f"Pensando...{model_tag}")

    def _handle_text(self, event: TextEvent) -> None:
        if not event.content:
            return

        if not self._streaming:
            self._streaming = True
            if not self._model and event.model:
                self._model = event.model
            self._spinner.stop()
            self._show_header()

        self._text_chunks.append(event.content)

    def _handle_tool_requests(self, event: ToolRequestsEvent) -> None:
        self._flush_remaining_text()

        if self._streaming:
            self._console.print()  # blank line after text

        self._spinner.stop()

        if event.conversation_id:
            self._conversation_id = event.conversation_id

        # Phase 1: Display tool calls but don't execute them
        if event.tool_calls:
            self._console.print()
            for tc in event.tool_calls:
                self._console.print(
                    f"  [agent.tool]\u2192 Tool:[/agent.tool] "
                    f"[agent.tool_name]{tc.name}[/agent.tool_name]"
                )
                # Show a compact preview of the input
                if tc.input:
                    import json
                    preview = json.dumps(tc.input, ensure_ascii=False)
                    if len(preview) > 100:
                        preview = preview[:97] + "..."
                    self._console.print(f"    [dim]{preview}[/dim]")

    def _handle_complete(self, event: CompleteEvent) -> None:
        self._flush_remaining_text()
        self._spinner.stop()

        if event.conversation_id:
            self._conversation_id = event.conversation_id

        elapsed = time.time() - self._start_time

        # Summary line
        self._console.print()
        parts = []

        if event.session_tokens > 0:
            parts.append(f"{event.session_tokens:,} tokens")

        if event.session_cost > 0:
            parts.append(f"${event.session_cost:.4f}")

        parts.append(f"{elapsed:.1f}s")

        if event.total_cost > 0:
            parts.append(f"total: ${event.total_cost:.4f}")

        summary = " · ".join(parts)
        self._console.print(f"  [dim]── {summary}[/dim]")

        if event.max_iterations_reached:
            self._console.print(
                "  [warning]Limite de iteraciones alcanzado[/warning]"
            )

    def _handle_error(self, event: ErrorEvent) -> None:
        self._spinner.stop()
        self._console.print()
        self._console.print(f"  [error]Error: {event.error}[/error]")

    def _handle_cost_warning(self, event: CostWarningEvent) -> None:
        self._console.print()
        self._console.print(
            f"  [cost.warning]Has usado {event.usage_percent:.0f}% "
            f"de tu limite mensual "
            f"(${event.remaining:.2f} restante de ${event.monthly_limit:.2f})[/cost.warning]"
        )

    def _handle_cost_limit(self, event: CostLimitExceededEvent) -> None:
        self._spinner.stop(
            f"Limite de coste mensual alcanzado "
            f"(${event.current_cost:.2f} / ${event.monthly_limit:.2f})",
            "error",
        )

    def _handle_rate_limited(self, event: RateLimitedEvent) -> None:
        self._spinner.stop(event.message or "Rate limit alcanzado", "info")

    def _handle_rag_search(self, event: RagSearchEvent) -> None:
        query_preview = event.query[:60]
        project_label = f" @{event.project_type}" if event.project_type else ""
        self._spinner.stop()
        self._console.print(
            f"  [agent.tool]Buscando{project_label}: \"{query_preview}...\"[/agent.tool]"
        )
        self._spinner.start("Buscando en codebase...")

    def _handle_rag_context(self, event: RagContextEvent) -> None:
        # Update RAG indicator
        if event.scope == "related":
            self._rag_indicator = f" [agent.rag_multi]\\[RAG:{event.chunks} multi-proyecto][/agent.rag_multi]"
        else:
            project_label = ""
            if event.project_type and event.project_type != "current":
                project_label = f" @{event.project_type}"
            self._rag_indicator = f" [agent.rag]\\[RAG:{event.chunks}{project_label}][/agent.rag]"

        self._spinner.stop()
        if event.chunks > 0:
            self._console.print(
                f"  [success]\u2713[/success] [agent.tool]Encontrados {event.chunks} chunks relevantes[/agent.tool]"
            )
        else:
            self._console.print(
                f"  [warning]\u25cb[/warning] [agent.tool]No se encontraron chunks relevantes[/agent.tool]"
            )
        self._spinner.start("Procesando respuesta...")

    def _handle_delegation(self, event: DelegationEvent) -> None:
        task_preview = event.task[:80]
        if len(event.task) > 80:
            task_preview += "..."
        self._spinner.stop()
        self._console.print(
            f"  [agent.delegation]Delegando a subagente:[/agent.delegation] "
            f"[agent.subagent]{event.subagent_id}[/agent.subagent]"
        )
        self._console.print(f"  [agent.tool]Tarea: {task_preview}[/agent.tool]")
        self._spinner.start(f"Subagente {event.subagent_id} trabajando...")

    def _handle_provider_fallback(self, event: ProviderFallbackEvent) -> None:
        self._spinner.stop()
        if event.reason == "insufficient_credits":
            msg = (
                f"  [warning]{event.failed_provider} sin creditos[/warning] "
                f"\u2192 [success]Usando {event.new_provider}[/success]"
            )
            if event.new_model:
                msg += f" [agent.model]({event.new_model})[/agent.model]"
            self._console.print(msg)
        else:
            self._console.print(
                f"  [warning]{event.message or f'Cambiando de {event.failed_provider} a {event.new_provider}'}[/warning]"
            )
        self._spinner.start(f"Procesando con {event.new_provider}...")

    def _handle_no_providers(self, event: NoProvidersAvailableEvent) -> None:
        self._spinner.stop()
        self._console.print()
        self._console.print(
            f"  [error]{event.message or 'No hay proveedores disponibles'}[/error]"
        )
        if event.providers_tried:
            self._console.print(
                f"  [dim]Proveedores intentados: {', '.join(event.providers_tried)}[/dim]"
            )

    def _handle_repaired(self, event: RepairedEvent) -> None:
        self._spinner.stop(
            "Conversacion recuperada (estaba interrumpida)", "info"
        )
        self._spinner.start("Continuando...")

    # ── Internal helpers ────────────────────────────────────────────────

    def _show_header(self) -> None:
        """Print the Agent response header."""
        if self._header_shown:
            return
        self._header_shown = True

        model_tag = f" [agent.model]({self._model})[/agent.model]" if self._model else ""
        self._console.print()
        self._console.print(
            f"  [agent.header]Agent:[/agent.header]{model_tag}{self._rag_indicator}"
        )
        self._console.print()

    def _flush_remaining_text(self) -> None:
        """Render any buffered text as markdown."""
        if not self._text_chunks:
            return

        full_text = "".join(self._text_chunks)

        if full_text.strip():
            if not self._header_shown:
                self._show_header()
            render_markdown(full_text)

        # Reset for next turn
        self._text_chunks.clear()
