#!/bin/bash

# Agent RAG Module
# Handles RAG (Retrieval Augmented Generation) integration with the server

# ============================================================================
# GIT REMOTE URL FUNCTIONS
# ============================================================================

# Get normalized git remote URL from current directory
# Returns HTTPS URL normalized (without .git suffix)
get_git_remote_url() {
    local url=$(git remote get-url origin 2>/dev/null)

    if [ -z "$url" ]; then
        echo ""
        return 1
    fi

    # Normalize URL using Python
    python3 -c "
import sys
url = '''$url'''.strip()

# Convert SSH to HTTPS
if url.startswith('git@'):
    # git@bitbucket.org:org/repo.git -> https://bitbucket.org/org/repo
    url = url.replace('git@', 'https://')
    url = url.replace(':', '/', 1)

# Remove .git suffix
if url.endswith('.git'):
    url = url[:-4]

# Remove trailing slash
url = url.rstrip('/')

print(url)
"
}

# ============================================================================
# RAG INDEX CHECK
# ============================================================================

# Check if project has RAG index on server
# Returns JSON: {has_index: bool, status: string, project_id: int, ...}
check_rag_index() {
    local git_remote_url=$(get_git_remote_url)

    if [ -z "$git_remote_url" ]; then
        echo '{"has_index": false, "status": "no_git_remote", "message": "No git remote configured"}'
        return 0
    fi

    local api_url=$(get_agent_config "api_url")
    local access_token=$(get_agent_config "access_token")
    local endpoint="$api_url/rag/check"

    # URL encode the git_remote_url
    local encoded_url=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$git_remote_url''', safe=''))")

    # Make request to check endpoint
    local response=$(curl -s -X GET \
        "$endpoint?git_remote_url=$encoded_url" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        2>/dev/null)

    if [ -z "$response" ]; then
        echo '{"has_index": false, "status": "error", "message": "Failed to connect to server"}'
        return 1
    fi

    # Parse response and add git_remote_url for reference
    python3 -c "
import json
import sys

try:
    data = json.loads('''$response''')

    # Handle error responses (list format from FastAPI)
    if isinstance(data, list):
        # Extract error message from list format
        error_msg = data[0].get('message', 'Unknown error') if data else 'Empty error response'
        print(json.dumps({
            'has_index': False,
            'status': 'error',
            'message': error_msg,
            'git_remote_url': '''$git_remote_url'''
        }))
    else:
        # Normal dict response
        data['git_remote_url'] = '''$git_remote_url'''
        print(json.dumps(data))
except Exception as e:
    print(json.dumps({
        'has_index': False,
        'status': 'error',
        'message': str(e),
        'git_remote_url': '''$git_remote_url'''
    }))
"
}

# ============================================================================
# RAG STATUS DISPLAY
# ============================================================================

# Display RAG status for current project (human-readable)
show_rag_status() {
    local rag_info=$(check_rag_index)

    local has_index=$(echo "$rag_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('has_index', False))" 2>/dev/null)
    local status=$(echo "$rag_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status', 'unknown'))" 2>/dev/null)
    local git_url=$(echo "$rag_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('git_remote_url', ''))" 2>/dev/null)
    local total_chunks=$(echo "$rag_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total_chunks', 0))" 2>/dev/null)
    local message=$(echo "$rag_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message', ''))" 2>/dev/null)

    # Colors
    local GREEN="\033[0;32m"
    local YELLOW="\033[1;33m"
    local RED="\033[0;31m"
    local CYAN="\033[0;36m"
    local DIM="\033[2m"
    local NC="\033[0m"
    local BOLD="\033[1m"

    echo -e "\n${BOLD}RAG Status${NC}"
    echo -e "${DIM}─────────────────────────────────────${NC}"

    if [ -z "$git_url" ] || [ "$status" = "no_git_remote" ]; then
        echo -e "  ${YELLOW}⚠${NC}  No git remote configurado"
        echo -e "     ${DIM}RAG requiere un repositorio git${NC}"
        return 1
    fi

    echo -e "  ${CYAN}Repository:${NC} $git_url"

    case "$status" in
        "ready")
            echo -e "  ${GREEN}●${NC} ${GREEN}Indexado${NC} - RAG activo"
            echo -e "     ${DIM}$total_chunks chunks disponibles${NC}"
            ;;
        "pending")
            echo -e "  ${YELLOW}●${NC} ${YELLOW}Pendiente${NC} - Esperando configuracion"
            [ -n "$message" ] && echo -e "     ${DIM}$message${NC}"
            ;;
        "indexing")
            echo -e "  ${CYAN}●${NC} ${CYAN}Indexando${NC} - En progreso..."
            ;;
        "error")
            echo -e "  ${RED}●${NC} ${RED}Error${NC} - Fallo en indexacion"
            [ -n "$message" ] && echo -e "     ${DIM}$message${NC}"
            ;;
        *)
            echo -e "  ${DIM}●${NC} Estado: $status"
            [ -n "$message" ] && echo -e "     ${DIM}$message${NC}"
            ;;
    esac

    echo ""
}

# ============================================================================
# RAG CONTEXT HELPER
# ============================================================================

# Check if RAG should be used for current project
# Returns 0 (true) if RAG is available and should be used
should_use_rag() {
    local rag_info=$(check_rag_index)
    local has_index=$(echo "$rag_info" | python3 -c "import sys,json; print('true' if json.load(sys.stdin).get('has_index') else 'false')" 2>/dev/null)

    [ "$has_index" = "true" ]
}

# Get git_remote_url and ensure project is registered for RAG
# This is used by agent_api.sh to include in requests
# Also triggers auto-registration of new projects
get_rag_git_url() {
    local git_url=$(get_git_remote_url)

    if [ -z "$git_url" ]; then
        echo ""
        return 0
    fi

    # Call check endpoint to auto-register project if new
    # This ensures the project exists in the RAG system
    local rag_info=$(check_rag_index 2>/dev/null)
    local status=$(echo "$rag_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status', 'unknown'))" 2>/dev/null)

    # Show message if project was just registered
    if [ "$status" = "pending" ]; then
        echo -e "  ${YELLOW}📋${NC} Proyecto registrado para RAG (pendiente de indexar)" >&2
    fi

    echo "$git_url"
}
