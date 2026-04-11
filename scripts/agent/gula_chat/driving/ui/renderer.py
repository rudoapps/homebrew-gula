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
    InternalCallEvent,
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
        self._session_cost: float = 0.0
        self._session_tokens: int = 0

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
        elif isinstance(event, InternalCallEvent):
            self._handle_internal_call(event)

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

        # Build RAG indicator (plain text for spinner)
        if event.rag_enabled and event.rag_info:
            scope = event.rag_info.get("scope", "current")
            chunks = event.rag_info.get("chunks", 0)
            if scope == "related":
                self._rag_indicator = f" [RAG:{chunks} multi-proyecto]"
            else:
                self._rag_indicator = f" [RAG:{chunks}]"
        elif event.rag_enabled:
            self._rag_indicator = " [RAG]"

        model_tag = f" ({event.model})" if event.model else ""
        self._spinner.start(f"#{event.conversation_id}{self._rag_indicator}{model_tag}")

    def _handle_thinking(self, event: ThinkingEvent) -> None:
        # Flush any accumulated text before showing spinner
        if self._text_chunks:
            self._flush_remaining_text()
            self._console.print()
        model_tag = f" ({event.model})" if event.model else ""
        cost_tag = f" · ${self._session_cost:.4f}" if self._session_cost > 0 else ""
        self._spinner.start(f"Pensando...{model_tag}{cost_tag}")

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

        # Track running cost
        if event.session_cost > 0:
            self._session_cost = event.session_cost
        if event.session_tokens > 0:
            self._session_tokens = event.session_tokens

        # Phase 1: Display tool calls
        if event.tool_calls:
            self._console.print()
            count = len(event.tool_calls)

            if count <= 3:
                # Few tools — show full detail
                for tc in event.tool_calls:
                    self._console.print(
                        f"  [agent.tool]\u2192 Tool:[/agent.tool] "
                        f"[agent.tool_name]{tc.name}[/agent.tool_name]"
                    )
                    if tc.input:
                        import json
                        preview = json.dumps(tc.input, ensure_ascii=False)
                        if len(preview) > 100:
                            preview = preview[:97] + "..."
                        self._console.print(f"    [dim]{preview}[/dim]")
            else:
                # Many tools — compact summary
                tool_names = [tc.name for tc in event.tool_calls]
                unique = sorted(set(tool_names))
                counts = {n: tool_names.count(n) for n in unique}
                summary_parts = []
                for name, c in counts.items():
                    summary_parts.append(f"{name}" + (f" x{c}" if c > 1 else ""))
                sep = " \u00b7 "
                self._console.print(
                    f"  [agent.tool]\u2192 {count} tools:[/agent.tool] "
                    f"[dim]{sep.join(summary_parts)}[/dim]"
                )

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
            session_str = f"${event.session_cost:.4f}"
            if event.session_internal_cost > 0:
                session_str += (
                    f" (+${event.session_internal_cost:.4f} internal)"
                )
            parts.append(session_str)

        parts.append(f"{elapsed:.1f}s")

        if event.total_cost > 0:
            total_str = f"total: ${event.total_cost:.4f}"
            if event.total_internal_cost > 0:
                total_str += f" (+${event.total_internal_cost:.4f} internal)"
            parts.append(total_str)

        summary = " · ".join(parts)
        self._console.print(f"  [dim]── {summary}[/dim]")

        # OS notification for long operations (>15s)
        if elapsed > 15:
            try:
                from ...driven.notifications.os_notify import send_notification
                cost_str = f" (${event.session_cost:.4f})" if event.session_cost > 0 else ""
                send_notification(
                    "gula - Respuesta lista",
                    f"Completado en {elapsed:.0f}s{cost_str}",
                )
            except Exception:
                pass

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

    def _handle_internal_call(self, event: InternalCallEvent) -> None:
        """Show a one-liner for an internal LLM call (compaction, classifier,
        RAG enhancer, subagent, …) so the user can see where time/cost goes."""
        # Map caller code → human label + emoji
        labels = {
            "compaction": ("🧠", "compaction"),
            "rag_enhancer_or_classifier": ("🏷", "classifier/RAG enhancer"),
            "rag_architecture_guide": ("📐", "RAG architecture guide"),
            "subagent": ("🤖", "subagent"),
            "subagent_fallback": ("🤖", "subagent (fallback)"),
            "llm_router": ("🔀", "llm router"),
            "llm_router_fallback": ("🔀", "llm router (fallback)"),
        }
        emoji, label = labels.get(event.caller, ("⚙", event.caller or "internal"))

        # Don't disturb the spinner — write a quiet inline line.
        was_spinning = (
            self._spinner.is_running() if hasattr(self._spinner, "is_running") else False
        )
        if was_spinning:
            self._spinner.stop()

        model_tag = f" ({event.model_id})" if event.model_id else ""
        cost_tag = f" · ${event.cost:.4f}" if event.cost > 0 else ""
        tok_tag = (
            f" · {event.total_tokens:,} tok" if event.total_tokens > 0 else ""
        )
        self._console.print(
            f"  [dim]{emoji} {label}{model_tag}{tok_tag}{cost_tag}[/dim]"
        )

        if was_spinning:
            # Restart a generic spinner — the next event will replace it
            self._spinner.start("Pensando...")

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
