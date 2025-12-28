#!/bin/bash

# Agent Chat Module
# Handles chat UI, interactive mode, and conversations

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
    [ -n "$elapsed" ] && [ "$elapsed" != "0" ] && stats="$stats ${DIM}|${NC} ${DIM}Tiempo:${NC} ${elapsed}s"

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

    local response
    response=$(run_hybrid_chat "$prompt" "")
    local run_status=$?

    # Handle auth errors - try refresh first, then prompt for login
    if [ $run_status -eq 2 ]; then
        if handle_auth_error; then
            echo -e "${BOLD}Reintentando...${NC}"
            response=$(run_hybrid_chat "$prompt" "")
            run_status=$?
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

    # Extract response data
    local text_response=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('response', ''))" 2>/dev/null)
    local conv_id=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('conversation_id', ''))" 2>/dev/null)
    local cost=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_cost', 0))" 2>/dev/null)
    local elapsed=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('elapsed_time', 0))" 2>/dev/null)
    local tokens=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_tokens', 0))" 2>/dev/null)
    local tools_count=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tools_count', 0))" 2>/dev/null)

    # Display response and summary
    display_response "$text_response"
    display_summary "$tokens" "$cost" "$elapsed" "$tools_count" "$conv_id"
}

# ============================================================================
# INTERACTIVE MODE
# ============================================================================

# Interactive chat mode
agent_chat_interactive() {
    local conversation_id=""
    local total_cost=0

    echo ""
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              GULA AGENT - MODO INTERACTIVO                ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Escribe tu mensaje y presiona Enter para enviarlo."
    echo -e "  Comandos especiales:"
    echo -e "    ${YELLOW}/exit${NC} o ${YELLOW}/quit${NC}  - Salir del chat"
    echo -e "    ${YELLOW}/new${NC}           - Nueva conversacion"
    echo -e "    ${YELLOW}/cost${NC}          - Ver costo acumulado"
    echo -e "    ${YELLOW}/clear${NC}         - Limpiar pantalla"
    echo -e "    ${YELLOW}/help${NC}          - Mostrar ayuda"
    echo ""
    echo -e "${BOLD}───────────────────────────────────────────────────────────────${NC}"
    echo ""

    while true; do
        # Show prompt
        echo -ne "${GREEN}> ${NC}"

        # Read user input
        local user_input
        read -r user_input

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
                echo -e "  ${YELLOW}/cost${NC}              - Ver costo acumulado"
                echo -e "  ${YELLOW}/clear${NC}             - Limpiar pantalla"
                echo -e "  ${YELLOW}/help${NC}              - Mostrar esta ayuda"
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
            local response
            response=$(run_hybrid_chat "$current_prompt" "$conversation_id")
            local run_status=$?

            # Handle auth errors - try refresh first, then prompt for login
            if [ $run_status -eq 2 ]; then
                if handle_auth_error; then
                    response=$(run_hybrid_chat "$current_prompt" "$conversation_id")
                    run_status=$?
                else
                    break
                fi
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
            local msg_elapsed=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('elapsed_time', 0))" 2>/dev/null)
            local msg_tokens=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_tokens', 0))" 2>/dev/null)
            local msg_tools=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tools_count', 0))" 2>/dev/null)
            local max_iter_reached=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('max_iterations_reached', False))" 2>/dev/null)

            # Update conversation ID if this is a new conversation
            if [ -z "$conversation_id" ] && [ -n "$new_conv_id" ]; then
                conversation_id="$new_conv_id"
            fi

            # Update total cost
            total_cost=$(python3 -c "print(round($total_cost + $msg_cost, 6))" 2>/dev/null || echo "$total_cost")

            # Display response
            display_response "$text_response"

            # Display summary
            echo ""
            echo -e "${DIM}─────────────────────────────────────────────${NC}"
            local summary_info=""
            [ "$msg_tools" -gt 0 ] 2>/dev/null && summary_info="${GREEN}✓${NC} ${msg_tools} tool(s) "
            [ -n "$msg_tokens" ] && [ "$msg_tokens" != "0" ] && summary_info="${summary_info}${DIM}Tokens:${NC} ${msg_tokens} "
            [ -n "$msg_cost" ] && summary_info="${summary_info}${DIM}|${NC} ${DIM}\$${NC}${msg_cost} "
            [ -n "$msg_elapsed" ] && [ "$msg_elapsed" != "0" ] && summary_info="${summary_info}${DIM}|${NC} ${msg_elapsed}s"
            echo -e "  ${summary_info}"
            echo -e "${DIM}─────────────────────────────────────────────${NC}"
            echo ""

            # Check if max iterations was reached
            if [ "$max_iter_reached" = "True" ]; then
                echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
                echo -e "${YELLOW}El agente ha alcanzado el limite de iteraciones.${NC}"
                echo -ne "${BOLD}Deseas que continue? (s/n): ${NC}"
                read -r continue_answer

                if [[ "$continue_answer" =~ ^[sS]$ ]]; then
                    current_prompt="continua"
                    echo ""
                else
                    continue_iterations=false
                fi
            else
                continue_iterations=false
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
