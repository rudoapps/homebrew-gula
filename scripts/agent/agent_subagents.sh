#!/bin/bash

# Agent Subagents Module
# Handles subagent listing and invocation from within chat

# ============================================================================
# FETCH SUBAGENTS FROM BACKEND
# ============================================================================

# Fetch subagents list from backend
# Returns JSON array or empty on error
fetch_subagents_from_backend() {
    local api_url=$(get_agent_config "api_url")
    local access_token=$(get_agent_config "access_token")

    local response=$(curl -s -w "\n%{http_code}" "$api_url/agent/subagents" \
        -H "Authorization: Bearer $access_token" 2>/dev/null)

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    # Check for auth errors
    if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
        echo "AUTH_ERROR"
        return 2
    fi

    # Check for success
    if [ "$http_code" = "200" ]; then
        echo "$body"
        return 0
    fi

    # Other errors
    echo "ERROR:$http_code"
    return 1
}

# ============================================================================
# LIST SUBAGENTS
# ============================================================================

# Show available subagents (fetched from backend)
show_available_subagents() {
    echo ""
    echo -e "${BOLD}Subagentes disponibles:${NC}"
    echo ""

    # Fetch from backend
    local response
    response=$(fetch_subagents_from_backend)
    local status=$?

    # Handle auth error
    if [ "$response" = "AUTH_ERROR" ]; then
        if handle_auth_error; then
            response=$(fetch_subagents_from_backend)
            status=$?
        else
            echo -e "  ${RED}Error: No autenticado${NC}"
            return 1
        fi
    fi

    # Handle other errors
    if [ $status -ne 0 ]; then
        echo -e "  ${RED}Error: No se pudo obtener la lista de subagentes${NC}"
        echo -e "  ${DIM}El servidor puede no tener este endpoint implementado${NC}"
        echo ""
        return 1
    fi

    # Parse and display subagents
    python3 -c "
import sys
import json

try:
    data = json.loads('''$response''')
    subagents = data.get('subagents', [])

    if not subagents:
        print('  No hay subagentes disponibles.')
    else:
        for sa in subagents:
            sid = sa.get('id', 'unknown')
            desc = sa.get('description', 'Sin descripcion')[:50]
            print(f'  \033[0;36m{sid:<16}\033[0m - {desc}')
except Exception as e:
    print(f'  \033[0;31mError parseando respuesta: {e}\033[0m')
    sys.exit(1)
"
    local parse_status=$?

    echo ""
    if [ $parse_status -eq 0 ]; then
        echo -e "Uso: ${YELLOW}/subagent <id> <mensaje>${NC}"
        echo -e "Ejemplo: ${DIM}/subagent code-review src/auth.py${NC}"
    fi
    echo ""
}

# ============================================================================
# VALIDATE SUBAGENT
# ============================================================================

# Check if subagent_id is valid (by querying backend)
is_valid_subagent() {
    local subagent_id="$1"

    # Fetch subagents and check if the ID exists
    local response
    response=$(fetch_subagents_from_backend)
    local status=$?

    if [ $status -ne 0 ]; then
        # If we can't reach backend, allow it and let the server validate
        return 0
    fi

    # Check if subagent_id exists in the list
    python3 -c "
import json
import sys

try:
    data = json.loads('''$response''')
    subagents = data.get('subagents', [])
    ids = [sa.get('id') for sa in subagents]
    if '$subagent_id' in ids:
        sys.exit(0)
    else:
        sys.exit(1)
except:
    sys.exit(0)  # Allow if can't parse, let server validate
"
}

# ============================================================================
# INVOKE SUBAGENT
# ============================================================================

# Invoke a subagent within the chat context
# This function is called from agent_chat_interactive
invoke_subagent_in_chat() {
    local subagent_id="$1"
    local prompt="$2"
    local conversation_id="$3"

    # Show subagent header (validation will be done by server)
    echo ""
    echo -e "${CYAN}[Subagente: $subagent_id]${NC}"
    echo ""

    # Call server with subagent_id
    local response
    response=$(run_hybrid_chat "$prompt" "$conversation_id" "15" "$subagent_id")
    local run_status=$?

    # Handle auth errors with refresh
    if [ $run_status -eq 2 ]; then
        if handle_auth_error; then
            echo -e "${BOLD}Reintentando...${NC}"
            response=$(run_hybrid_chat "$prompt" "$conversation_id" "15" "$subagent_id")
            run_status=$?
        else
            return 1
        fi
    fi

    # Check for errors
    local error=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error') or '')" 2>/dev/null)
    if [ -n "$error" ] && [ "$error" != "None" ]; then
        echo -e "${RED}Error: $error${NC}"
        return 1
    fi

    # Extract response data
    local text_response=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('response', ''))" 2>/dev/null)
    local new_conv_id=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('conversation_id', ''))" 2>/dev/null)
    local msg_cost=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total_cost', 0))" 2>/dev/null)
    local msg_tokens=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total_tokens', 0))" 2>/dev/null)
    local msg_elapsed=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('elapsed_time', 0))" 2>/dev/null)
    local msg_tools=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tools_count', 0))" 2>/dev/null)

    # Display response using existing display_response function
    display_response "$text_response"

    # Display subagent-specific summary
    echo ""
    echo -e "${DIM}─────────────────────────────────────────────${NC}"
    local summary_info="${CYAN}[$subagent_id]${NC} "
    [ "$msg_tools" -gt 0 ] 2>/dev/null && summary_info="${summary_info}${GREEN}✓${NC} ${msg_tools} tool(s) "
    [ -n "$msg_tokens" ] && [ "$msg_tokens" != "0" ] && summary_info="${summary_info}${DIM}Tokens:${NC} ${msg_tokens} "
    [ -n "$msg_cost" ] && summary_info="${summary_info}${DIM}|${NC} ${DIM}\$${NC}${msg_cost} "
    [ -n "$msg_elapsed" ] && [ "$msg_elapsed" != "0" ] && summary_info="${summary_info}${DIM}|${NC} ${msg_elapsed}s"
    echo -e "  ${summary_info}"
    echo -e "${DIM}─────────────────────────────────────────────${NC}"

    # Return the new conversation_id if it was created
    echo "$new_conv_id"
}
