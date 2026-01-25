#!/bin/bash

# Agent Chat Module
# Handles chat UI, interactive mode, and conversations

# ============================================================================
# ERROR FORMATTING
# ============================================================================

# Display formatted error with cause and solutions
# Usage: show_formatted_error "title" "cause" "solution1" "solution2" ...
show_formatted_error() {
    local title="$1"
    local cause="$2"
    shift 2
    local solutions=("$@")

    echo ""
    echo -e "${RED}┌─${NC} ${RED}✗ Error${NC} ${RED}─────────────────────────────────────────${NC}"
    echo -e "${RED}│${NC}"
    echo -e "${RED}│${NC}  ${BOLD}${title}${NC}"

    if [ -n "$cause" ]; then
        echo -e "${RED}│${NC}"
        echo -e "${RED}│${NC}  ${DIM}Causa:${NC} ${cause}"
    fi

    if [ ${#solutions[@]} -gt 0 ]; then
        echo -e "${RED}│${NC}"
        echo -e "${RED}│${NC}  ${YELLOW}💡 Soluciones:${NC}"
        for solution in "${solutions[@]}"; do
            echo -e "${RED}│${NC}     ${DIM}•${NC} ${solution}"
        done
    fi

    echo -e "${RED}│${NC}"
    echo -e "${RED}└─────────────────────────────────────────────────${NC}"
    echo ""
}

# ============================================================================
# MULTI-LINE INPUT
# ============================================================================

# Read multi-line input with readline support for keyboard shortcuts
# Supports:
# - Ctrl+A: Go to start of line
# - Ctrl+E: Go to end of line
# - Ctrl+W: Delete word backward
# - Ctrl+K: Delete to end of line
# - Ctrl+U: Delete to start of line
# - Arrow keys: Move cursor / navigate history
# - Single line: press Enter to submit
# - Multi-line: type \ at end of line to continue, or Enter twice to submit
read_multiline_input() {
    local lines=()
    local line=""
    local is_first_line=true

    while true; do
        # Show prompt
        if [ "$is_first_line" = true ]; then
            echo -ne "${CYAN}›${NC} " >&2
        else
            echo -ne "${DIM}  ...${NC} " >&2
        fi

        # Read input with readline support (-e enables readline editing)
        if ! IFS= read -e -r line; then
            # EOF - return what we have
            break
        fi

        # Check for backslash continuation
        if [[ "$line" == *"\\" ]]; then
            # Remove trailing backslash and continue
            line="${line%\\}"
            lines+=("$line")
            is_first_line=false
            continue
        fi

        # Check for empty line (submit signal in multi-line mode)
        if [ -z "$line" ]; then
            if [ ${#lines[@]} -gt 0 ]; then
                # We have content and got empty line - submit
                break
            else
                # Empty input on first line - return empty
                echo ""
                return
            fi
        fi

        # Add line to buffer
        lines+=("$line")

        # For single line input (first line, no continuation), submit immediately
        if [ "$is_first_line" = true ]; then
            break
        fi

        is_first_line=false
    done

    # Join lines with newlines
    local result=""
    local first=true
    for l in "${lines[@]}"; do
        if [ "$first" = true ]; then
            result="$l"
            first=false
        else
            result="$result"$'\n'"$l"
        fi
    done

    echo "$result"
}

# ============================================================================
# TYPING INDICATOR (Spinner)
# ============================================================================

# PID del proceso de spinner (global para poder matarlo)
TYPING_INDICATOR_PID=""

# Mostrar indicador de typing (spinner animado)
# Ejecutar en background: show_typing_indicator &
show_typing_indicator() {
    local message="${1:-Pensando...}"
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    local start_time=$(date +%s)

    # Ocultar cursor
    printf "\033[?25l" >&2

    while true; do
        local elapsed=$(($(date +%s) - start_time))
        printf "\r\033[2K  \033[0;36m${frames[$i]}\033[0m %s \033[2m(%ds)\033[0m" "$message" "$elapsed" >&2
        i=$(( (i + 1) % 10 ))
        sleep 0.08
    done
}

# Detener indicador de typing
stop_typing_indicator() {
    if [ -n "$TYPING_INDICATOR_PID" ]; then
        kill "$TYPING_INDICATOR_PID" 2>/dev/null
        wait "$TYPING_INDICATOR_PID" 2>/dev/null
        TYPING_INDICATOR_PID=""
    fi
    # Limpiar línea y mostrar cursor
    printf "\r\033[2K\033[?25h" >&2
}

# Asegurar que el spinner se detenga y cursor se restaure al salir (Ctrl+C, etc.)
cleanup_on_exit() {
    stop_typing_indicator
    # Always ensure cursor is visible
    printf "\033[?25h" >&2
}
trap 'cleanup_on_exit' EXIT INT TERM

# ============================================================================
# INTERACTIVE SELECTOR
# ============================================================================

# Interactive option selector with arrow keys
# Usage: selected=$(interactive_select "Pregunta?" "Opción 1" "Opción 2" "Opción 3")
# Returns: the selected option text
interactive_select() {
    local prompt="$1"
    shift
    local options=("$@")

    python3 - "$prompt" "${options[@]}" << 'PYEOF'
import sys
import tty
import termios

# Colors
BOLD = "\033[1m"
DIM = "\033[2m"
NC = "\033[0m"
CYAN = "\033[0;36m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"

# Cursor control
HIDE_CURSOR = "\033[?25l"
SHOW_CURSOR = "\033[?25h"
CLEAR_LINE = "\033[2K"
MOVE_UP = "\033[A"

def get_key():
    """Read a single keypress."""
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = sys.stdin.read(1)
        if ch == '\x1b':  # Escape sequence
            ch2 = sys.stdin.read(1)
            if ch2 == '[':
                ch3 = sys.stdin.read(1)
                if ch3 == 'A': return 'up'
                if ch3 == 'B': return 'down'
            return 'esc'
        if ch in ('\r', '\n'): return 'enter'
        if ch == '\x03': return 'ctrl-c'  # Ctrl+C
        return ch
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

def render(prompt, options, selected_idx, first_render=False):
    """Render the selector."""
    # Move up to clear previous render (except first time)
    if not first_render:
        # Move up: 1 for prompt + number of options
        for _ in range(len(options) + 1):
            sys.stderr.write(f"{MOVE_UP}{CLEAR_LINE}")

    # Print prompt
    sys.stderr.write(f"{BOLD}{prompt}{NC}\n")

    # Print options
    for i, opt in enumerate(options):
        if i == selected_idx:
            sys.stderr.write(f"  {GREEN}❯{NC} {BOLD}{opt}{NC}\n")
        else:
            sys.stderr.write(f"    {DIM}{opt}{NC}\n")

    sys.stderr.flush()

# Get arguments
prompt = sys.argv[1]
options = sys.argv[2:]

if not options:
    print("")
    sys.exit(1)

selected_idx = 0

# Hide cursor
sys.stderr.write(HIDE_CURSOR)
sys.stderr.flush()

try:
    render(prompt, options, selected_idx, first_render=True)

    while True:
        key = get_key()

        if key == 'up':
            selected_idx = (selected_idx - 1) % len(options)
            render(prompt, options, selected_idx)
        elif key == 'down':
            selected_idx = (selected_idx + 1) % len(options)
            render(prompt, options, selected_idx)
        elif key == 'enter':
            break
        elif key in ('esc', 'ctrl-c', 'q'):
            # Return empty on cancel
            sys.stderr.write(SHOW_CURSOR)
            sys.stderr.flush()
            print("")
            sys.exit(0)

finally:
    sys.stderr.write(SHOW_CURSOR)
    sys.stderr.flush()

# Output selected option
print(options[selected_idx])
PYEOF
}

# ============================================================================
# RESPONSE DISPLAY
# ============================================================================

# Display response with markdown rendering
display_response() {
    local text_response="$1"
    local model_name="${2:-}"

    echo ""
    # Response header with model info
    if [ -n "$model_name" ]; then
        echo -e "${DIM}╭─${NC} ${BOLD}Agent${NC} ${DIM}($model_name) ────────────────────────────────────────────╮${NC}"
    else
        echo -e "${DIM}╭─${NC} ${BOLD}Agent${NC} ${DIM}─────────────────────────────────────────────────────────╮${NC}"
    fi
    echo ""

    # Render markdown with glow if available
    if command -v glow &> /dev/null; then
        echo "$text_response" | glow -s dark -w 80 -
    else
        # Simple markdown to ANSI conversion
        echo "$text_response" | python3 -c "
import sys
import re

text = sys.stdin.read()

# Bold: **text** or __text__
text = re.sub(r'\*\*(.+?)\*\*', '\033[1m\\1\033[0m', text)
text = re.sub(r'__(.+?)__', '\033[1m\\1\033[0m', text)

# Inline code: \`code\`
text = re.sub(r'\`([^\`]+)\`', '\033[36m\\1\033[0m', text)

# Headers
text = re.sub(r'^### (.+)$', '\033[1;35m\\1\033[0m', text, flags=re.MULTILINE)
text = re.sub(r'^## (.+)$', '\033[1;34m\\1\033[0m', text, flags=re.MULTILINE)
text = re.sub(r'^# (.+)$', '\033[1;33m\\1\033[0m', text, flags=re.MULTILINE)

# Bullet points
text = re.sub(r'^(\s*)[-*] ', r'\\1• ', text, flags=re.MULTILINE)

# Numbered lists
text = re.sub(r'^(\s*)(\d+)\. ', r'\\1\033[33m\\2.\033[0m ', text, flags=re.MULTILINE)

print(text)
"
    fi
}

# Display summary after response
display_summary() {
    local tokens="$1"
    local cost="$2"
    local elapsed="$3"
    local tools_count="$4"
    local conv_id="$5"

    echo ""

    # Build summary line with separators
    local summary_parts=""

    # Tools indicator
    if [ "$tools_count" -gt 0 ] 2>/dev/null; then
        summary_parts="${GREEN}✓${NC} ${tools_count} tools"
    fi

    # Stats
    [ -n "$tokens" ] && [ "$tokens" != "0" ] && summary_parts="$summary_parts · ${tokens} tokens"
    if [ -n "$cost" ]; then
        local cost_fmt=$(python3 -c "
cost = float('${cost:-0}')
if cost >= 0.01:
    fmt = f'{cost:.2f}'
elif cost >= 0.001:
    fmt = f'{cost:.4f}'
else:
    fmt = f'{cost:.6f}'.rstrip('0').rstrip('.')
print(fmt)
" 2>/dev/null || echo "$cost")
        summary_parts="$summary_parts · \$$cost_fmt"
    fi
    [ -n "$elapsed" ] && [ "$elapsed" != "0" ] && summary_parts="$summary_parts · ${elapsed}s"

    # Remove leading separator if no tools
    summary_parts="${summary_parts# · }"

    # Display in box
    echo -e "${DIM}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${DIM}│${NC}  $summary_parts"
    echo -e "${DIM}└──────────────────────────────────────────────────────────────┘${NC}"
}

# ============================================================================
# SINGLE MESSAGE CHAT
# ============================================================================

# Agent chat - single message mode
agent_chat_single() {
    local prompt="$1"

    show_project_info
    echo ""

    # Mostrar indicador de typing inmediatamente
    show_typing_indicator "Pensando..." &
    TYPING_INDICATOR_PID=$!
    disown $TYPING_INDICATOR_PID 2>/dev/null  # Evitar mensaje "Killed" al terminar
    # Exportar PID para que send_chat_hybrid pueda detenerlo
    export GULA_TYPING_PID=$TYPING_INDICATOR_PID

    local response run_status
    # Temporarily disable errexit to capture non-zero return codes
    set +e
    response=$(run_hybrid_chat "$prompt" "")
    run_status=$?
    set -e

    # Asegurar que el typing indicator esté detenido
    stop_typing_indicator
    unset GULA_TYPING_PID

    # Handle auth errors - try refresh first, then prompt for login
    if [ $run_status -eq 2 ]; then
        if handle_auth_error; then
            echo -e "${BOLD}Reintentando...${NC}"
            set +e
            response=$(run_hybrid_chat "$prompt" "")
            run_status=$?
            set -e
        else
            return 1
        fi
    fi

    # Check for other errors
    local error=$(json_get_error "$response")

    if [ -n "$error" ] && [ "$error" != "None" ]; then
        echo -e "${RED}Error: $error${NC}"
        return 1
    fi

    # Check if conversation was repaired (interrupted session)
    if json_is_true "$response" "repaired"; then
        echo ""
        echo -e "  ${YELLOW}⚠️  La conversacion estaba interrumpida y fue recuperada.${NC}"
        echo -e "  ${DIM}Puedes continuar escribiendo tu siguiente mensaje.${NC}"
        echo ""
        return 0
    fi

    # Extract response data
    local text_response=$(json_get "$response" "response")
    local conv_id=$(json_get "$response" "conversation_id")
    local cost=$(json_get_num "$response" "total_cost")
    local elapsed=$(json_get_num "$response" "elapsed_time")
    local tokens=$(json_get_num "$response" "total_tokens")
    local tools_count=$(json_get_num "$response" "tools_count")
    local total_elapsed=$(json_get_num "$response" "total_elapsed")
    local text_streamed=$(json_get "$response" "text_streamed")

    # Use total_elapsed if available (includes tool execution time)
    [ -n "$total_elapsed" ] && [ "$total_elapsed" != "0" ] && elapsed="$total_elapsed"

    # Display response (skip if already streamed)
    # Note: Python json outputs lowercase "true"
    if [ "$text_streamed" != "True" ] && [ "$text_streamed" != "true" ]; then
        display_response "$text_response"
    fi
    display_summary "$tokens" "$cost" "$elapsed" "$tools_count" "$conv_id"
}

# ============================================================================
# INTERACTIVE MODE
# ============================================================================

# Interactive chat mode
agent_chat_interactive() {
    local conversation_id=""
    local total_cost=0

    # Try to recover last conversation for this project
    local saved_conv_id=$(get_project_conversation)

    echo ""

    # Header line: 📁 folder · ↩ #conv · /new nueva · /help comandos
    local project_name=$(basename "$PWD")
    local header_line="📁 ${BOLD}$project_name${NC}"
    if [ -n "$saved_conv_id" ]; then
        conversation_id="$saved_conv_id"
        header_line="$header_line ${DIM}·${NC} ${DIM}↩${NC} #$conversation_id"
    fi
    header_line="$header_line ${DIM}·${NC} ${WHITE}/new${NC} ${DIM}nueva${NC} ${DIM}·${NC} ${WHITE}/help${NC} ${DIM}comandos${NC}"
    echo -e "$header_line"

    # Build status bar
    local status_parts=""

    # RAG status
    local rag_git_url=$(get_rag_git_url 2>/dev/null)
    if [ -n "$rag_git_url" ]; then
        local rag_response=$(check_rag_index 2>/dev/null)
        local rag_status=$(json_get "$rag_response" "status")
        case "$rag_status" in
            "ready")
                status_parts="${GREEN}●${NC} RAG"
                ;;
            "pending")
                status_parts="${YELLOW}○${NC} RAG ${DIM}pendiente${NC}"
                ;;
            "indexing")
                status_parts="${CYAN}◐${NC} RAG ${DIM}indexando${NC}"
                ;;
            *)
                status_parts="${DIM}○ RAG${NC}"
                ;;
        esac
    else
        status_parts="${DIM}○ RAG${NC}"
    fi

    # Quota/Presupuesto status
    local quota_str=$(get_quota_status_inline)
    if [ -n "$quota_str" ]; then
        status_parts="$status_parts  │  $quota_str"
    fi

    echo -e "${DIM}───────────────────────────────────────────────────────────────${NC}"
    echo -e " $status_parts"
    echo -e "${DIM}───────────────────────────────────────────────────────────────${NC}"

    while true; do
        # Read multi-line input
        local user_input
        user_input=$(read_multiline_input)

        # Handle empty input
        if [ -z "$user_input" ]; then
            continue
        fi

        # Handle special commands
        case "$user_input" in
            /exit|/quit|/q)
                echo ""
                echo -e "${YELLOW}Saliendo del chat...${NC}"
                if [ -n "$conversation_id" ]; then
                    echo -e "Conversacion ID: ${BOLD}$conversation_id${NC}"
                fi
                # Format cost with appropriate precision (use Python for locale-independent formatting)
                local exit_cost_fmt=$(python3 -c "
cost = float('${total_cost:-0}')
if cost >= 0.01:
    fmt = f'{cost:.2f}'
elif cost >= 0.001:
    fmt = f'{cost:.4f}'
else:
    fmt = f'{cost:.6f}'.rstrip('0').rstrip('.')
print(fmt)
" 2>/dev/null || echo "$total_cost")
                echo -e "Costo total de la sesion: ${BOLD}\$${exit_cost_fmt}${NC}"
                echo -e "${GREEN}Hasta luego!${NC}"
                echo ""
                return 0
                ;;
            /new)
                conversation_id=""
                clear_project_conversation
                echo -e "${YELLOW}Nueva conversacion iniciada.${NC}"
                echo ""
                continue
                ;;
            /cost)
                local cost_cmd_fmt=$(python3 -c "
cost = float('${total_cost:-0}')
if cost >= 0.01:
    fmt = f'{cost:.2f}'
elif cost >= 0.001:
    fmt = f'{cost:.4f}'
else:
    fmt = f'{cost:.6f}'.rstrip('0').rstrip('.')
print(fmt)
" 2>/dev/null || echo "$total_cost")
                echo -e "Costo acumulado: ${BOLD}\$${cost_cmd_fmt}${NC}"
                if [ -n "$conversation_id" ]; then
                    echo -e "Conversacion actual: ${BOLD}$conversation_id${NC}"
                fi
                echo ""
                continue
                ;;
            /clear)
                clear
                echo -e "${BOLD}GULA AGENT - Chat Interactivo${NC}"
                echo -e "${BOLD}───────────────────────────────────────────────────────────────${NC}"
                echo ""
                continue
                ;;
            /help)
                echo ""
                echo -e "${BOLD}Comandos disponibles:${NC}"
                echo -e "  ${YELLOW}/exit${NC}, ${YELLOW}/quit${NC}, ${YELLOW}/q${NC}  - Salir del chat"
                echo -e "  ${YELLOW}/new${NC}               - Iniciar nueva conversacion"
                echo -e "  ${YELLOW}/resume <id>${NC}       - Retomar conversacion por ID"
                echo -e "  ${YELLOW}/cost${NC}              - Ver costo acumulado de la sesion"
                echo -e "  ${YELLOW}/presupuesto${NC}       - Ver limite y uso mensual"
                echo -e "  ${YELLOW}/clear${NC}             - Limpiar pantalla"
                echo -e "  ${YELLOW}/help${NC}              - Mostrar esta ayuda"
                echo -e "  ${YELLOW}/debug${NC}             - Activar/desactivar modo debug"
                echo ""
                echo -e "${BOLD}Modelos:${NC}"
                echo -e "  ${YELLOW}/models${NC}            - Ver modelos disponibles"
                echo -e "  ${YELLOW}/model <id>${NC}        - Cambiar modelo (ej: /model sonnet)"
                echo -e "  ${YELLOW}/model auto${NC}        - Usar routing automatico"
                echo ""
                echo -e "${BOLD}Subagentes:${NC}"
                echo -e "  ${YELLOW}/subagents${NC}         - Listar subagentes disponibles"
                echo -e "  ${YELLOW}/subagent <id> <msg>${NC} - Invocar un subagente"
                echo ""
                echo -e "${BOLD}Entrada multi-linea:${NC}"
                echo -e "  - Escribe \\ al final de una linea para continuar"
                echo -e "  - Al pegar texto, presiona Enter dos veces para enviar"
                echo ""
                echo -e "${BOLD}Imagenes:${NC}"
                echo -e "  - Incluye rutas de imagenes en tu mensaje:"
                echo -e "    ${DIM}Que ves en ~/Desktop/screenshot.png?${NC}"
                echo ""
                continue
                ;;
            /quota|/presupuesto)
                fetch_and_show_quota
                continue
                ;;
            /models)
                show_available_models
                continue
                ;;
            /model)
                # Show current model
                local current=$(get_agent_config "preferred_model")
                if [ -n "$current" ] && [ "$current" != "null" ]; then
                    echo -e "Modelo actual: ${BOLD}$current${NC}"
                else
                    echo -e "Modelo actual: ${DIM}auto (routing automatico)${NC}"
                fi
                echo -e "${DIM}Usa /models para ver opciones disponibles${NC}"
                echo ""
                continue
                ;;
            /model\ *)
                # Change model
                local new_model="${user_input#/model }"
                if [ "$new_model" = "auto" ] || [ "$new_model" = "default" ]; then
                    set_agent_config "preferred_model" "null"
                    echo -e "${GREEN}✓${NC} Modelo: ${BOLD}auto${NC} (routing automatico)"
                    echo -e "${DIM}El sistema elegira el modelo segun el tipo de tarea${NC}"
                else
                    set_agent_config "preferred_model" "$new_model"
                    echo -e "${GREEN}✓${NC} Modelo cambiado a: ${BOLD}$new_model${NC}"
                    echo -e "${DIM}Todas las siguientes peticiones usaran este modelo${NC}"
                fi
                echo ""
                continue
                ;;
            /debug)
                local current_debug=$(get_agent_config "debug_mode")
                if [ "$current_debug" = "true" ]; then
                    set_agent_config "debug_mode" "false"
                    echo -e "${YELLOW}Debug mode desactivado${NC}"
                else
                    set_agent_config "debug_mode" "true"
                    echo -e "${GREEN}Debug mode activado${NC}"
                    echo -e "${DIM}Verás información de diagnóstico en las peticiones${NC}"
                fi
                echo ""
                continue
                ;;
            /resume\ *)
                local resume_id="${user_input#/resume }"
                if [[ "$resume_id" =~ ^[0-9]+$ ]]; then
                    conversation_id="$resume_id"
                    echo -e "${GREEN}Conversacion #$conversation_id retomada.${NC}"
                    echo -e "${DIM}Escribe tu mensaje para continuar.${NC}"
                else
                    echo -e "${RED}ID de conversacion invalido: $resume_id${NC}"
                    echo -e "Uso: ${YELLOW}/resume 123${NC}"
                fi
                echo ""
                continue
                ;;
            /subagents)
                show_available_subagents
                continue
                ;;
            /subagent\ *)
                # Extract subagent_id and prompt from: /subagent <id> <mensaje>
                local rest="${user_input#/subagent }"
                local subagent_id="${rest%% *}"
                local subagent_prompt="${rest#* }"

                # Check if only ID was provided without message
                if [ "$subagent_id" = "$subagent_prompt" ] || [ -z "$subagent_prompt" ]; then
                    echo -e "${RED}Uso: /subagent <id> <mensaje>${NC}"
                    echo -e "Ejemplo: ${DIM}/subagent code-review src/auth.py${NC}"
                    echo -e "Usa ${YELLOW}/subagents${NC} para ver los subagentes disponibles"
                    echo ""
                    continue
                fi

                # Invoke subagent and capture new conversation_id if created
                local new_conv_id
                new_conv_id=$(invoke_subagent_in_chat "$subagent_id" "$subagent_prompt" "$conversation_id")

                # Update conversation_id if a new one was created
                if [ -z "$conversation_id" ] && [ -n "$new_conv_id" ] && [ "$new_conv_id" != "None" ]; then
                    conversation_id="$new_conv_id"
                fi
                echo ""
                continue
                ;;
            /*)
                echo -e "${RED}Comando desconocido: $user_input${NC}"
                echo -e "Escribe ${YELLOW}/help${NC} para ver los comandos disponibles."
                echo ""
                continue
                ;;
        esac

        # Send message with continuation loop
        local current_prompt="$user_input"
        local continue_iterations=true

        # Mostrar indicador de typing inmediatamente
        show_typing_indicator "Pensando..." &
        TYPING_INDICATOR_PID=$!
        disown $TYPING_INDICATOR_PID 2>/dev/null  # Evitar mensaje "Killed" al terminar
        # Exportar PID para que send_chat_hybrid pueda detenerlo
        export GULA_TYPING_PID=$TYPING_INDICATOR_PID

        while [ "$continue_iterations" = true ]; do
            echo ""

            # Use hybrid mode - tools execute locally
            local response run_status
            # Temporarily disable errexit to capture non-zero return codes
            set +e
            response=$(run_hybrid_chat "$current_prompt" "$conversation_id")
            run_status=$?

            # Asegurar que el typing indicator esté detenido después de cada llamada
            # Keep errexit disabled - kill/wait can fail if process already dead
            stop_typing_indicator
            unset GULA_TYPING_PID
            set -e

            # Check for empty or invalid response
            if [ -z "$response" ] || [ "$response" = "{}" ]; then
                show_formatted_error \
                    "No se recibió respuesta del servidor" \
                    "La conexión terminó inesperadamente" \
                    "Verifica tu conexión a internet" \
                    "Verifica que el servidor esté activo" \
                    "Intenta de nuevo en unos momentos"
                break
            fi

            # Handle auth errors - try refresh first, then prompt for login
            if [ $run_status -eq 2 ]; then
                if handle_auth_error; then
                    set +e
                    response=$(run_hybrid_chat "$current_prompt" "$conversation_id")
                    run_status=$?
                    set -e
                else
                    break
                fi
            fi

            # Check for rate limit (not an error - just wait)
            if json_is_true "$response" "rate_limited"; then
                local rate_msg=$(json_get "$response" "rate_limit_message" "Rate limit alcanzado")
                # Update conversation_id if provided
                local rate_conv_id=$(json_get "$response" "conversation_id")
                if [ -n "$rate_conv_id" ] && [ "$rate_conv_id" != "None" ] && [ "$rate_conv_id" != "null" ]; then
                    conversation_id="$rate_conv_id"
                    save_project_conversation "$conversation_id"
                fi
                echo ""
                echo -e "${YELLOW}⚠️  $rate_msg${NC}"
                echo -e "${DIM}Conversacion: #$conversation_id${NC}"
                echo -e "${DIM}Espera unos segundos y escribe otro mensaje para continuar.${NC}"
                echo -e "${DIM}(Si sales, usa /resume $conversation_id para retomar)${NC}"
                echo ""
                break  # Exit inner loop but stay in interactive mode
            fi

            # Check for errors
            local error=$(json_get "$response" "error")

            if [ -n "$error" ] && [ "$error" != "None" ]; then
                # Provide contextual error messages based on error type
                if [[ "$error" == *"inesperadamente"* ]] || [[ "$error" == *"timeout"* ]]; then
                    show_formatted_error \
                        "Timeout o conexión interrumpida" \
                        "$error" \
                        "Intenta con un mensaje más corto" \
                        "Verifica tu conexión a internet" \
                        "Espera unos momentos y reintenta"
                elif [[ "$error" == *"Connection"* ]] || [[ "$error" == *"connection"* ]]; then
                    show_formatted_error \
                        "Error de conexión" \
                        "$error" \
                        "Verifica tu conexión a internet" \
                        "Verifica que el servidor esté activo: https://agent.rudo.es" \
                        "Intenta de nuevo en unos momentos"
                elif [[ "$error" == *"Not Found"* ]] || [[ "$error" == *"404"* ]]; then
                    show_formatted_error \
                        "Servidor no disponible" \
                        "$error" \
                        "El servidor puede estar en mantenimiento" \
                        "Contacta al administrador" \
                        "Intenta de nuevo más tarde"
                else
                    show_formatted_error "$error" "" "Intenta de nuevo" "Si el problema persiste, contacta soporte"
                fi
                break
            fi

            # Check if operation was aborted by user (ESC key)
            if json_is_true "$response" "aborted"; then
                local completed_tools=$(json_get_num "$response" "completed_tools")
                local total_tools=$(json_get_num "$response" "total_tools")
                local abort_conv_id=$(json_get "$response" "conversation_id")

                # Update conversation ID if available
                if [ -n "$abort_conv_id" ] && [ "$abort_conv_id" != "None" ] && [ "$abort_conv_id" != "null" ]; then
                    conversation_id="$abort_conv_id"
                    save_project_conversation "$conversation_id"
                fi

                echo ""
                echo -e "${YELLOW}⚡ Operación cancelada${NC} ${DIM}($completed_tools/$total_tools herramientas ejecutadas)${NC}"
                echo -e "${DIM}La conversación #$conversation_id sigue activa.${NC}"
                echo -e "${DIM}Escribe otro mensaje para continuar o dar nuevas instrucciones.${NC}"
                echo ""
                break  # Exit inner loop but stay in interactive mode
            fi

            # Extract response data - disable errexit to prevent crashes on missing fields
            set +e
            local text_response=$(json_get "$response" "response" 2>/dev/null || echo "")
            local new_conv_id=$(json_get "$response" "conversation_id" 2>/dev/null || echo "")
            local msg_cost=$(json_get_num "$response" "total_cost" 2>/dev/null || echo "0")
            local session_cost=$(json_get_num "$response" "session_cost" 2>/dev/null || echo "0")
            local msg_elapsed=$(json_get_num "$response" "elapsed_time" 2>/dev/null || echo "0")
            local msg_tokens=$(json_get_num "$response" "total_tokens" 2>/dev/null || echo "0")
            local session_tokens=$(json_get_num "$response" "session_tokens" 2>/dev/null || echo "0")
            local msg_tools=$(json_get_num "$response" "tools_count" 2>/dev/null || echo "0")
            local max_iter_reached=$(json_get "$response" "max_iterations_reached" 2>/dev/null || echo "")
            local total_elapsed=$(json_get_num "$response" "total_elapsed" 2>/dev/null || echo "0")
            local text_streamed=$(json_get "$response" "text_streamed" 2>/dev/null || echo "")
            set -e

            # Update conversation ID if this is a new conversation
            if [ -z "$conversation_id" ] && [ -n "$new_conv_id" ] && [ "$new_conv_id" != "None" ] && [ "$new_conv_id" != "null" ]; then
                conversation_id="$new_conv_id"
                # Save for future sessions
                save_project_conversation "$conversation_id"
            fi

            # Update total cost (protect against empty values)
            set +e
            [ -z "$msg_cost" ] && msg_cost=0
            total_cost=$(python3 -c "print(round(${total_cost:-0} + ${msg_cost:-0}, 6))" 2>/dev/null || echo "$total_cost")
            set -e

            # Display response (or notice if empty)
            # Skip if text was already streamed to the terminal
            # Note: Python json outputs lowercase "true", bash comparison is case-sensitive
            if [ "$text_streamed" = "True" ] || [ "$text_streamed" = "true" ]; then
                : # Text was already shown during streaming
            elif [ -z "$text_response" ] || [ "$text_response" = "None" ]; then
                echo ""
                echo -e "${YELLOW}Agent:${NC}"
                echo ""
                echo -e "${DIM}(El agente ejecutó herramientas pero no generó respuesta de texto)${NC}"
                echo -e "${DIM}Escribe otro mensaje para continuar o pedir explicación.${NC}"
            else
                # Disable errexit for display_response (glow or python could fail)
                set +e
                display_response "$text_response"
                set -e
            fi

            # Display enhanced summary box - disable errexit to prevent crashes on formatting
            set +e
            echo ""
            echo -e "${DIM}┌─${NC} ${BOLD}Resumen${NC} ${DIM}──────────────────────────────────────────────────${NC}"
            echo -e "${DIM}│${NC}"

            # Line 1: Session duration (formatted)
            if [ -n "$total_elapsed" ] && [ "$total_elapsed" != "0" ]; then
                local duration_fmt=$(python3 -c "
t = ${total_elapsed}
if t >= 60:
    m = int(t / 60)
    s = int(t % 60)
    print(f'{m}m {s}s')
else:
    print(f'{int(t)}s')
" 2>/dev/null || echo "${total_elapsed}s")
                echo -e "${DIM}│${NC}  ⏱  Duración: ${BOLD}${duration_fmt}${NC}"
            fi

            # Line 2: Tools executed (with breakdown by type)
            local tools_count=${msg_tools:-0}
            if [ "$tools_count" != "0" ] && [ "$tools_count" != "" ]; then
                # Get tool details from response if available
                local tool_breakdown=$(json_get "$response" "tool_breakdown" 2>/dev/null || echo "")
                if [ -n "$tool_breakdown" ] && [ "$tool_breakdown" != "null" ]; then
                    echo -e "${DIM}│${NC}  🔧 Herramientas: ${BOLD}${tools_count}${NC}"
                    echo -e "${DIM}│${NC}     ${DIM}${tool_breakdown}${NC}"
                else
                    echo -e "${DIM}│${NC}  🔧 Herramientas: ${BOLD}${tools_count}${NC}"
                fi
            fi

            # Line 3: Cost and tokens (this run)
            if [ -n "$session_tokens" ] && [ "$session_tokens" != "0" ]; then
                [ -z "$session_cost" ] && session_cost=0
                local session_cost_fmt=$(python3 -c "print(f'{float(${session_cost:-0}):.4f}')" 2>/dev/null || echo "0.0000")
                echo -e "${DIM}│${NC}  💰 Costo: ${BOLD}\$${session_cost_fmt}${NC}  ${DIM}(${session_tokens} tokens)${NC}"
            fi

            echo -e "${DIM}└────────────────────────────────────────────────────────────────${NC}"
            echo ""
            set -e

            # Show status bar (RAG + Presupuesto) after each response
            # Disable errexit for status bar - these are non-critical
            set +e
            local status_parts=""
            local rag_git_url=$(get_rag_git_url 2>/dev/null || echo "")
            if [ -n "$rag_git_url" ]; then
                local rag_response=$(check_rag_index 2>/dev/null || echo "{}")
                local rag_status=$(json_get "$rag_response" "status" 2>/dev/null || echo "")
                case "$rag_status" in
                    "ready") status_parts="${GREEN}●${NC} RAG" ;;
                    "pending") status_parts="${YELLOW}○${NC} RAG ${DIM}pendiente${NC}" ;;
                    "indexing") status_parts="${CYAN}◐${NC} RAG ${DIM}indexando${NC}" ;;
                    *) status_parts="${DIM}○ RAG${NC}" ;;
                esac
            else
                status_parts="${DIM}○ RAG${NC}"
            fi
            local quota_str=$(get_quota_status_inline 2>/dev/null || echo "")
            if [ -n "$quota_str" ]; then
                status_parts="$status_parts  │  $quota_str"
            fi
            set -e
            echo -e "${DIM}───────────────────────────────────────────────────────────────${NC}"
            echo -e " $status_parts"
            echo -e "${DIM}───────────────────────────────────────────────────────────────${NC}"

            # Check if max iterations was reached (server-side)
            if [ "$max_iter_reached" = "True" ] || [ "$max_iter_reached" = "true" ]; then
                echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
                echo -e "${YELLOW}El agente ha alcanzado el limite de iteraciones del servidor.${NC}"
                echo ""
                local continue_choice=$(interactive_select "¿Qué deseas hacer?" "Continuar" "Detener")

                if [ "$continue_choice" = "Continuar" ]; then
                    current_prompt="continua"
                    echo ""
                else
                    continue_iterations=false
                fi
            else
                continue_iterations=false
            fi

            # Check if max tool iterations was reached (client-side safety limit)
            if json_is_true "$response" "max_tool_iterations_reached"; then
                echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
                echo -e "${YELLOW}El agente ha ejecutado muchas herramientas (20+ en esta sesión).${NC}"
                echo -e "${DIM}Esto es un limite de seguridad para evitar bucles infinitos.${NC}"
                echo ""
                local tool_choice=$(interactive_select "¿Qué deseas hacer?" "Continuar" "Detener")

                if [ "$tool_choice" = "Continuar" ]; then
                    current_prompt="continua con la tarea"
                    continue_iterations=true
                    echo ""
                fi
            fi
        done

        # Disable errexit before going back to read input - prevents exit on EOF or read errors
        set +e

        # Visual separator and hint that user can continue
        echo -e "${DIM}───────────────────────────────────────────────────────────────${NC}"
        echo ""
    done
}

# ============================================================================
# MAIN CHAT ENTRY
# ============================================================================

# Agent chat - main entry point
agent_chat() {
    init_agent_config

    # Check dependencies on first run
    if ! ensure_agent_dependencies; then
        return 1
    fi

    # Verify authentication and token validity (with auto-refresh)
    if is_agent_authenticated; then
        if ! ensure_valid_token_with_refresh; then
            echo -e "${YELLOW}Tu sesion ha expirado y no se pudo renovar.${NC}"
            echo ""
            set_agent_config "access_token" "null"
            set_agent_config "refresh_token" "null"
        fi
    fi

    # If not authenticated (or refresh failed), trigger login
    if ! is_agent_authenticated; then
        echo -e "${YELLOW}No hay sesion activa. Iniciando login...${NC}"
        echo ""
        if ! agent_login; then
            echo -e "${RED}No se pudo iniciar sesion.${NC}"
            return 1
        fi
        echo ""
    fi

    local prompt="${1:-}"

    # If no prompt provided, enter interactive mode
    if [ -z "$prompt" ]; then
        agent_chat_interactive
        return $?
    fi

    # Single message mode
    agent_chat_single "$prompt"
}

# ============================================================================
# CONVERSATIONS
# ============================================================================

# List conversations
agent_conversations() {
    init_agent_config

    # Verify authentication and token validity (with auto-refresh)
    if is_agent_authenticated; then
        if ! ensure_valid_token_with_refresh; then
            echo -e "${YELLOW}Tu sesion ha expirado y no se pudo renovar.${NC}"
            echo ""
            set_agent_config "access_token" "null"
            set_agent_config "refresh_token" "null"
        fi
    fi

    # If not authenticated (or refresh failed), trigger login
    if ! is_agent_authenticated; then
        echo -e "${YELLOW}No hay sesion activa. Iniciando login...${NC}"
        echo ""
        if ! agent_login; then
            echo -e "${RED}No se pudo iniciar sesion.${NC}"
            return 1
        fi
        echo ""
    fi

    local api_url=$(get_agent_config "api_url")
    local access_token=$(get_agent_config "access_token")

    echo -e "${BOLD}-----------------------------------------------${NC}"
    echo -e "${BOLD}Conversaciones${NC}"
    echo -e "${BOLD}-----------------------------------------------${NC}"

    local response=$(curl -s "$api_url/agent/conversations" \
        -H "Authorization: Bearer $access_token")

    # Check for errors
    local error=$(json_get_error "$response")

    if [ -n "$error" ] && [ "$error" != "None" ]; then
        # Check if it's an auth error
        if [[ "$error" == *"Not authenticated"* ]] || [[ "$error" == *"token"* ]] || \
           [[ "$error" == *"expired"* ]] || [[ "$error" == *"authentication"* ]]; then
            if handle_auth_error; then
                # Retry the request
                access_token=$(get_agent_config "access_token")
                response=$(curl -s "$api_url/agent/conversations" \
                    -H "Authorization: Bearer $access_token")
                error=$(json_get_error "$response")
                if [ -n "$error" ] && [ "$error" != "None" ]; then
                    echo -e "${RED}Error: $error${NC}"
                    return 1
                fi
            else
                return 1
            fi
        else
            echo -e "${RED}Error: $error${NC}"
            return 1
        fi
    fi

    # Display conversations
    python3 -c "
import sys
import json

data = json.load(sys.stdin)
conversations = data.get('conversations', [])

if not conversations:
    print('No hay conversaciones.')
else:
    for conv in conversations:
        status = 'activa' if conv.get('is_active', False) else 'archivada'
        print(f\"ID: {conv['id']} | {conv['title'][:50]}... | Costo: \${conv['total_cost']:.6f} | {status}\")
" <<< "$response"
}
