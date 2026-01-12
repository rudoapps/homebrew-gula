#!/bin/bash

# Agent Chat Module
# Handles chat UI, interactive mode, and conversations

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
        # Show prompt with block indicator
        if [ "$is_first_line" = true ]; then
            echo -ne "${GREEN}█${NC} " >&2
        else
            echo -ne "${DIM}█${NC} " >&2
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
# RESPONSE DISPLAY
# ============================================================================

# Display response with markdown rendering
display_response() {
    local text_response="$1"

    echo ""
    echo -e "${BOLD}${YELLOW}Agent:${NC}"
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
    echo -e "${DIM}───────────────────────────────────────────────────${NC}"

    # Build summary parts
    local summary_parts=""
    if [ "$tools_count" -gt 0 ] 2>/dev/null; then
        summary_parts="${GREEN}✓${NC} ${tools_count} herramienta(s) ejecutada(s)"
    fi

    # Stats line
    local stats=""
    [ -n "$tokens" ] && [ "$tokens" != "0" ] && stats="${DIM}Tokens:${NC} $tokens"
    [ -n "$cost" ] && stats="$stats ${DIM}|${NC} ${DIM}Costo:${NC} \$$cost"
    [ -n "$elapsed" ] && [ "$elapsed" != "0" ] && stats="$stats ${DIM}|${NC} ${BOLD}${elapsed}s total${NC}"

    [ -n "$summary_parts" ] && echo -e "  $summary_parts"
    echo -e "  $stats"
    [ -n "$conv_id" ] && echo -e "  ${DIM}Conversacion:${NC} #$conv_id"
    echo -e "${DIM}───────────────────────────────────────────────────${NC}"
}

# ============================================================================
# SINGLE MESSAGE CHAT
# ============================================================================

# Agent chat - single message mode
agent_chat_single() {
    local prompt="$1"

    echo -e "${BOLD}Analizando proyecto y enviando mensaje...${NC}"
    show_project_info
    echo ""

    local response run_status
    # Temporarily disable errexit to capture non-zero return codes
    set +e
    response=$(run_hybrid_chat "$prompt" "")
    run_status=$?
    set -e

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
    local error=$(echo "$response" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('error', d.get('detail', '')))" 2>/dev/null)

    if [ -n "$error" ] && [ "$error" != "None" ]; then
        echo -e "${RED}Error: $error${NC}"
        return 1
    fi

    # Check if conversation was repaired (interrupted session)
    local was_repaired=$(echo "$response" | python3 -c "import sys, json; print('yes' if json.load(sys.stdin).get('repaired') else 'no')" 2>/dev/null)
    if [ "$was_repaired" = "yes" ]; then
        echo ""
        echo -e "  ${YELLOW}⚠️  La conversacion estaba interrumpida y fue recuperada.${NC}"
        echo -e "  ${DIM}Puedes continuar escribiendo tu siguiente mensaje.${NC}"
        echo ""
        return 0
    fi

    # Extract response data
    local text_response=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('response', ''))" 2>/dev/null)
    local conv_id=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('conversation_id', ''))" 2>/dev/null)
    local cost=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_cost', 0))" 2>/dev/null)
    local elapsed=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('elapsed_time', 0))" 2>/dev/null)
    local tokens=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_tokens', 0))" 2>/dev/null)
    local tools_count=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tools_count', 0))" 2>/dev/null)
    local total_elapsed=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_elapsed', 0))" 2>/dev/null)
    local text_streamed=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('text_streamed', False))" 2>/dev/null)

    # Use total_elapsed if available (includes tool execution time)
    [ -n "$total_elapsed" ] && [ "$total_elapsed" != "0" ] && elapsed="$total_elapsed"

    # Display response (skip if already streamed)
    if [ "$text_streamed" != "True" ]; then
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
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                         gula chat                             ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ -n "$saved_conv_id" ]; then
        conversation_id="$saved_conv_id"
        echo -e " ↩ #$conversation_id recuperada · ${WHITE}/new${NC} ${DIM}nueva${NC} · ${WHITE}/help${NC} ${DIM}comandos${NC}"
    else
        echo -e " ${WHITE}/help${NC} ${DIM}comandos${NC}"
    fi

    echo ""

    # Build status bar
    local status_parts=""

    # RAG status
    local rag_git_url=$(get_rag_git_url 2>/dev/null)
    if [ -n "$rag_git_url" ]; then
        local rag_status=$(check_rag_index 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
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
    echo ""

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
                echo -e "Costo total de la sesion: ${BOLD}\$$total_cost${NC}"
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
                echo -e "Costo acumulado: ${BOLD}\$$total_cost${NC}"
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

        while [ "$continue_iterations" = true ]; do
            echo ""

            # Use hybrid mode - tools execute locally
            local response run_status
            # Temporarily disable errexit to capture non-zero return codes
            set +e
            response=$(run_hybrid_chat "$current_prompt" "$conversation_id")
            run_status=$?
            set -e

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
            local rate_limited=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('rate_limited', False))" 2>/dev/null)
            if [ "$rate_limited" = "True" ]; then
                local rate_msg=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('rate_limit_message', 'Rate limit alcanzado'))" 2>/dev/null)
                # Update conversation_id if provided
                local rate_conv_id=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('conversation_id', ''))" 2>/dev/null)
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
            local error=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('error') or '')" 2>/dev/null)

            if [ -n "$error" ] && [ "$error" != "None" ]; then
                echo -e "${RED}Error: $error${NC}"
                echo ""
                break
            fi

            # Extract response data
            local text_response=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('response', ''))" 2>/dev/null)
            local new_conv_id=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('conversation_id', ''))" 2>/dev/null)
            local msg_cost=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_cost', 0))" 2>/dev/null)
            local session_cost=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('session_cost', 0))" 2>/dev/null)
            local msg_elapsed=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('elapsed_time', 0))" 2>/dev/null)
            local msg_tokens=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_tokens', 0))" 2>/dev/null)
            local session_tokens=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('session_tokens', 0))" 2>/dev/null)
            local msg_tools=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tools_count', 0))" 2>/dev/null)
            local max_iter_reached=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('max_iterations_reached', False))" 2>/dev/null)
            local total_elapsed=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_elapsed', 0))" 2>/dev/null)
            local text_streamed=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('text_streamed', False))" 2>/dev/null)

            # Update conversation ID if this is a new conversation
            if [ -z "$conversation_id" ] && [ -n "$new_conv_id" ] && [ "$new_conv_id" != "None" ] && [ "$new_conv_id" != "null" ]; then
                conversation_id="$new_conv_id"
                # Save for future sessions
                save_project_conversation "$conversation_id"
            fi

            # Update total cost
            total_cost=$(python3 -c "print(round($total_cost + $msg_cost, 6))" 2>/dev/null || echo "$total_cost")

            # Display response (or notice if empty)
            # Skip if text was already streamed to the terminal
            if [ "$text_streamed" = "True" ]; then
                : # Text was already shown during streaming
            elif [ -z "$text_response" ] || [ "$text_response" = "None" ]; then
                echo ""
                echo -e "${YELLOW}Agent:${NC}"
                echo ""
                echo -e "${DIM}(El agente ejecutó herramientas pero no generó respuesta de texto)${NC}"
                echo -e "${DIM}Escribe otro mensaje para continuar o pedir explicación.${NC}"
            else
                display_response "$text_response"
            fi

            # Display summary box
            echo ""
            echo -e "${DIM}┌──────────────────────────────────────────────────────────────┐${NC}"

            # Line 1: Session info (this run)
            local session_line="  ${GREEN}✓${NC} Esta ejecución: "
            if [ -n "$session_tokens" ] && [ "$session_tokens" != "0" ]; then
                local session_cost_fmt=$(python3 -c "print(f'{float($session_cost):.4f}')" 2>/dev/null || echo "0.0000")
                session_line="${session_line}${BOLD}${session_tokens}${NC} tokens  ${BOLD}\$${session_cost_fmt}${NC}"
            else
                session_line="${session_line}${DIM}sin llamadas LLM${NC}"
            fi
            if [ -n "$total_elapsed" ] && [ "$total_elapsed" != "0" ]; then
                session_line="${session_line}  ${DIM}(${total_elapsed}s)${NC}"
            fi
            echo -e "${DIM}│${NC}${session_line}"

            # Line 2: Total conversation info
            if [ -n "$msg_tokens" ] && [ "$msg_tokens" != "0" ]; then
                local total_cost_fmt=$(python3 -c "print(f'{float($msg_cost):.4f}')" 2>/dev/null || echo "0.0000")
                echo -e "${DIM}│  ${NC}${DIM}Total conversación: ${msg_tokens} tokens  \$${total_cost_fmt}${NC}"
            fi

            # Line 3: Tools if any
            if [ "$msg_tools" -gt 0 ] 2>/dev/null; then
                echo -e "${DIM}│  ${NC}${DIM}Herramientas: ${msg_tools}${NC}"
            fi

            echo -e "${DIM}└──────────────────────────────────────────────────────────────┘${NC}"
            echo ""

            # Show status bar (RAG + Presupuesto) after each response
            local status_parts=""
            local rag_git_url=$(get_rag_git_url 2>/dev/null)
            if [ -n "$rag_git_url" ]; then
                local rag_status=$(check_rag_index 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
                case "$rag_status" in
                    "ready") status_parts="${GREEN}●${NC} RAG" ;;
                    "pending") status_parts="${YELLOW}○${NC} RAG ${DIM}pendiente${NC}" ;;
                    "indexing") status_parts="${CYAN}◐${NC} RAG ${DIM}indexando${NC}" ;;
                    *) status_parts="${DIM}○ RAG${NC}" ;;
                esac
            else
                status_parts="${DIM}○ RAG${NC}"
            fi
            local quota_str=$(get_quota_status_inline)
            if [ -n "$quota_str" ]; then
                status_parts="$status_parts  │  $quota_str"
            fi
            echo -e "${DIM}───────────────────────────────────────────────────────────────${NC}"
            echo -e " $status_parts"
            echo ""

            # Check if max iterations was reached (server-side)
            if [ "$max_iter_reached" = "True" ]; then
                echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
                echo -e "${YELLOW}El agente ha alcanzado el limite de iteraciones del servidor.${NC}"
                echo -ne "${BOLD}Deseas que continue? (s/n/si/continua): ${NC}"
                read -r continue_answer

                if [[ "$continue_answer" =~ ^([sS]|[sS][iI]|[cC]ontinua)$ ]]; then
                    current_prompt="continua"
                    echo ""
                else
                    continue_iterations=false
                fi
            else
                continue_iterations=false
            fi

            # Check if max tool iterations was reached (client-side safety limit)
            local max_tool_iter_reached=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('max_tool_iterations_reached', False))" 2>/dev/null)
            if [ "$max_tool_iter_reached" = "True" ]; then
                echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
                echo -e "${YELLOW}El agente ha ejecutado muchas herramientas (20+ en esta sesión).${NC}"
                echo -e "${DIM}Esto es un limite de seguridad para evitar bucles infinitos.${NC}"
                echo -ne "${BOLD}Deseas que continue? (s/n/si/continua): ${NC}"
                read -r continue_answer

                if [[ "$continue_answer" =~ ^([sS]|[sS][iI]|[cC]ontinua)$ ]]; then
                    current_prompt="continua con la tarea"
                    continue_iterations=true
                    echo ""
                fi
            fi
        done

        echo -e "${BOLD}───────────────────────────────────────────────────────────────${NC}"
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
    local error=$(echo "$response" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('error', d.get('detail', '')))" 2>/dev/null)

    if [ -n "$error" ] && [ "$error" != "None" ]; then
        # Check if it's an auth error
        if [[ "$error" == *"Not authenticated"* ]] || [[ "$error" == *"token"* ]] || \
           [[ "$error" == *"expired"* ]] || [[ "$error" == *"authentication"* ]]; then
            if handle_auth_error; then
                # Retry the request
                access_token=$(get_agent_config "access_token")
                response=$(curl -s "$api_url/agent/conversations" \
                    -H "Authorization: Bearer $access_token")
                error=$(echo "$response" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('error', d.get('detail', '')))" 2>/dev/null)
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
