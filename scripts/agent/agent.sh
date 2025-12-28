#!/bin/bash

# Agent CLI module for Gula
# Provides interaction with the Agentic AI server

# Get script directory
AGENT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar modulos
source "$AGENT_SCRIPT_DIR/agent_local_tools.sh"
source "$AGENT_SCRIPT_DIR/agent_ui.sh"

# Configuration
AGENT_CONFIG_DIR="$HOME/.config/gula-agent"
AGENT_CONFIG_FILE="$AGENT_CONFIG_DIR/config.json"
AGENT_SETUP_DONE_FILE="$AGENT_CONFIG_DIR/.setup_done"
AGENT_API_URL="${AGENT_API_URL:-http://localhost:8002/api/v1}"

# Required dependencies
AGENT_REQUIRED_DEPS=("python3" "curl")
AGENT_OPTIONAL_DEPS=("glow")

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check all agent dependencies
check_agent_dependencies() {
    local missing_required=()
    local missing_optional=()

    for dep in "${AGENT_REQUIRED_DEPS[@]}"; do
        if ! command_exists "$dep"; then
            missing_required+=("$dep")
        fi
    done

    for dep in "${AGENT_OPTIONAL_DEPS[@]}"; do
        if ! command_exists "$dep"; then
            missing_optional+=("$dep")
        fi
    done

    if [ ${#missing_required[@]} -gt 0 ]; then
        echo "required:${missing_required[*]}"
        return 1
    fi

    if [ ${#missing_optional[@]} -gt 0 ]; then
        echo "optional:${missing_optional[*]}"
        return 2
    fi

    return 0
}

# Install agent dependencies via Homebrew
install_agent_dependencies() {
    echo -e "${BOLD}-----------------------------------------------${NC}"
    echo -e "${BOLD}Instalacion de dependencias del Agent${NC}"
    echo -e "${BOLD}-----------------------------------------------${NC}"
    echo ""

    # Check for Homebrew
    if ! command_exists brew; then
        echo -e "${RED}Error: Homebrew no esta instalado.${NC}"
        echo -e "Instala Homebrew desde: ${YELLOW}https://brew.sh${NC}"
        echo ""
        echo -e "Ejecuta: ${BOLD}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
        return 1
    fi

    echo -e "${GREEN}✓${NC} Homebrew encontrado"
    echo ""

    local deps_to_install=()
    local optional_to_install=()

    # Check required dependencies
    echo -e "${BOLD}Verificando dependencias requeridas...${NC}"
    for dep in "${AGENT_REQUIRED_DEPS[@]}"; do
        if command_exists "$dep"; then
            echo -e "  ${GREEN}✓${NC} $dep instalado"
        else
            echo -e "  ${RED}✗${NC} $dep no encontrado"
            deps_to_install+=("$dep")
        fi
    done

    # Check optional dependencies
    echo ""
    echo -e "${BOLD}Verificando dependencias opcionales...${NC}"
    for dep in "${AGENT_OPTIONAL_DEPS[@]}"; do
        if command_exists "$dep"; then
            echo -e "  ${GREEN}✓${NC} $dep instalado"
        else
            echo -e "  ${YELLOW}○${NC} $dep no encontrado (recomendado)"
            optional_to_install+=("$dep")
        fi
    done

    echo ""

    # Install required dependencies
    if [ ${#deps_to_install[@]} -gt 0 ]; then
        echo -e "${BOLD}Instalando dependencias requeridas...${NC}"
        for dep in "${deps_to_install[@]}"; do
            echo -e "  Instalando ${YELLOW}$dep${NC}..."
            if brew install "$dep" &> /dev/null; then
                echo -e "  ${GREEN}✓${NC} $dep instalado correctamente"
            else
                echo -e "  ${RED}✗${NC} Error instalando $dep"
                return 1
            fi
        done
        echo ""
    fi

    # Ask about optional dependencies
    if [ ${#optional_to_install[@]} -gt 0 ]; then
        echo -e "${BOLD}Dependencias opcionales disponibles:${NC}"
        for dep in "${optional_to_install[@]}"; do
            case "$dep" in
                glow)
                    echo -e "  ${YELLOW}glow${NC} - Renderizado de Markdown en terminal (mejor experiencia visual)"
                    ;;
                *)
                    echo -e "  ${YELLOW}$dep${NC}"
                    ;;
            esac
        done
        echo ""
        read -p "Deseas instalar las dependencias opcionales? (s/n): " install_optional

        if [[ "$install_optional" =~ ^[sS]$ ]]; then
            for dep in "${optional_to_install[@]}"; do
                echo -e "  Instalando ${YELLOW}$dep${NC}..."
                if brew install "$dep" &> /dev/null; then
                    echo -e "  ${GREEN}✓${NC} $dep instalado correctamente"
                else
                    echo -e "  ${YELLOW}!${NC} No se pudo instalar $dep (continuando...)"
                fi
            done
        fi
        echo ""
    fi

    # Mark setup as done
    mkdir -p "$AGENT_CONFIG_DIR"
    touch "$AGENT_SETUP_DONE_FILE"

    echo -e "${GREEN}-----------------------------------------------${NC}"
    echo -e "${GREEN}Instalacion completada!${NC}"
    echo -e "${GREEN}-----------------------------------------------${NC}"
    echo ""
    echo -e "Ahora puedes usar: ${BOLD}gula agent chat${NC}"
    return 0
}

# Check dependencies and prompt setup if needed
ensure_agent_dependencies() {
    # Skip if setup was already done
    if [ -f "$AGENT_SETUP_DONE_FILE" ]; then
        return 0
    fi

    local check_result
    check_result=$(check_agent_dependencies)
    local status=$?

    if [ $status -eq 1 ]; then
        # Missing required dependencies
        local missing="${check_result#required:}"
        echo -e "${RED}Error: Faltan dependencias requeridas: ${missing}${NC}"
        echo ""
        read -p "Deseas ejecutar el setup ahora? (s/n): " run_setup
        if [[ "$run_setup" =~ ^[sS]$ ]]; then
            install_agent_dependencies
            return $?
        else
            echo -e "${YELLOW}Ejecuta 'gula agent setup' para instalar las dependencias.${NC}"
            return 1
        fi
    elif [ $status -eq 2 ]; then
        # Missing optional dependencies - just warn once
        local missing="${check_result#optional:}"
        echo -e "${YELLOW}Nota: Algunas dependencias opcionales no estan instaladas: ${missing}${NC}"
        echo -e "${YELLOW}Ejecuta 'gula agent setup' para instalarlas y mejorar la experiencia.${NC}"
        echo ""
        # Mark as done to not show warning again
        mkdir -p "$AGENT_CONFIG_DIR"
        touch "$AGENT_SETUP_DONE_FILE"
    fi

    return 0
}

# Initialize config directory
init_agent_config() {
    mkdir -p "$AGENT_CONFIG_DIR"
    if [ ! -f "$AGENT_CONFIG_FILE" ]; then
        echo '{"api_url":"'"$AGENT_API_URL"'","access_token":null,"refresh_token":null}' > "$AGENT_CONFIG_FILE"
    fi
}

# Get value from config
get_agent_config() {
    local key=$1
    if [ -f "$AGENT_CONFIG_FILE" ]; then
        python3 -c "import json; print(json.load(open('$AGENT_CONFIG_FILE')).get('$key', ''))" 2>/dev/null || echo ""
    fi
}

# Set value in config
set_agent_config() {
    local key=$1
    local value=$2
    if [ -f "$AGENT_CONFIG_FILE" ]; then
        python3 -c "
import json
config = json.load(open('$AGENT_CONFIG_FILE'))
config['$key'] = '$value' if '$value' != 'null' else None
json.dump(config, open('$AGENT_CONFIG_FILE', 'w'), indent=2)
"
    fi
}

# Check if authenticated
is_agent_authenticated() {
    local token=$(get_agent_config "access_token")
    [ -n "$token" ] && [ "$token" != "None" ] && [ "$token" != "null" ]
}

# Agent login via browser
agent_login() {
    init_agent_config

    local api_url=$(get_agent_config "api_url")
    [ -z "$api_url" ] && api_url="$AGENT_API_URL"

    echo -e "${BOLD}-----------------------------------------------${NC}"
    echo -e "${BOLD}Agent Login${NC}"
    echo -e "${BOLD}-----------------------------------------------${NC}"

    # Check if already authenticated
    if is_agent_authenticated; then
        echo -e "${YELLOW}Ya estas autenticado.${NC}"
        read -p "Deseas volver a iniciar sesion? (s/n): " CONFIRM
        if [ "$CONFIRM" != "s" ]; then
            echo -e "${GREEN}Sesion activa.${NC}"
            return 0
        fi
    fi

    echo -e "Creando sesion de autenticacion..."

    # Create session
    local response=$(curl -s -X POST "$api_url/cli-auth/session")
    local session_id=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('session_id', ''))" 2>/dev/null)

    if [ -z "$session_id" ]; then
        echo -e "${RED}Error: No se pudo crear la sesion de autenticacion${NC}"
        echo -e "${RED}Respuesta: $response${NC}"
        return 1
    fi

    # Open browser
    local login_url="$api_url/cli-auth/login?session=$session_id"
    echo -e "${GREEN}Abriendo navegador para login...${NC}"
    echo -e "URL: $login_url"

    # Open browser (macOS specific, could be extended for Linux)
    if command -v open &> /dev/null; then
        open "$login_url"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$login_url"
    else
        echo -e "${YELLOW}No se pudo abrir el navegador automaticamente.${NC}"
        echo -e "Abre esta URL manualmente: $login_url"
    fi

    echo ""
    echo -e "${BOLD}Esperando autenticacion en el navegador...${NC}"
    echo -e "(Presiona Ctrl+C para cancelar)"

    # Poll for completion
    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        sleep 2
        local poll_response=$(curl -s "$api_url/cli-auth/poll?session=$session_id")
        local status=$(echo "$poll_response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', ''))" 2>/dev/null)

        case "$status" in
            "completed")
                local access_token=$(echo "$poll_response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null)
                local refresh_token=$(echo "$poll_response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('refresh_token', ''))" 2>/dev/null)
                local user_email=$(echo "$poll_response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('user_email', ''))" 2>/dev/null)

                set_agent_config "access_token" "$access_token"
                set_agent_config "refresh_token" "$refresh_token"
                set_agent_config "user_email" "$user_email"

                echo ""
                echo -e "${GREEN}-----------------------------------------------${NC}"
                echo -e "${GREEN}Login exitoso!${NC}"
                echo -e "${GREEN}Usuario: $user_email${NC}"
                echo -e "${GREEN}-----------------------------------------------${NC}"
                return 0
                ;;
            "pending")
                printf "."
                ;;
            "expired")
                echo ""
                echo -e "${RED}La sesion ha expirado. Intenta de nuevo.${NC}"
                return 1
                ;;
            "not_found")
                echo ""
                echo -e "${RED}Sesion no encontrada.${NC}"
                return 1
                ;;
        esac

        attempt=$((attempt + 1))
    done

    echo ""
    echo -e "${RED}Tiempo de espera agotado. Intenta de nuevo.${NC}"
    return 1
}

# Agent logout
agent_logout() {
    init_agent_config

    echo -e "${BOLD}-----------------------------------------------${NC}"
    echo -e "${BOLD}Agent Logout${NC}"
    echo -e "${BOLD}-----------------------------------------------${NC}"

    if ! is_agent_authenticated; then
        echo -e "${YELLOW}No hay sesion activa.${NC}"
        return 0
    fi

    set_agent_config "access_token" "null"
    set_agent_config "refresh_token" "null"
    set_agent_config "user_email" "null"

    echo -e "${GREEN}Sesion cerrada correctamente.${NC}"
}

# Agent status
agent_status() {
    init_agent_config

    echo -e "${BOLD}-----------------------------------------------${NC}"
    echo -e "${BOLD}Agent Status${NC}"
    echo -e "${BOLD}-----------------------------------------------${NC}"

    local api_url=$(get_agent_config "api_url")
    echo -e "API URL: ${YELLOW}$api_url${NC}"

    if is_agent_authenticated; then
        local user_email=$(get_agent_config "user_email")
        echo -e "Estado: ${GREEN}Autenticado${NC}"
        echo -e "Usuario: ${GREEN}$user_email${NC}"

        # Verificar si el token sigue siendo valido
        if validate_agent_token; then
            echo -e "Token: ${GREEN}Valido${NC}"
        else
            echo -e "Token: ${YELLOW}Expirado${NC}"
            # Check if we can refresh
            local refresh_token=$(get_agent_config "refresh_token")
            if [ -n "$refresh_token" ] && [ "$refresh_token" != "None" ] && [ "$refresh_token" != "null" ]; then
                echo -e "Refresh: ${GREEN}Disponible${NC} (se renovara automaticamente)"
            else
                echo -e "Refresh: ${RED}No disponible${NC}"
                echo -e "Ejecuta: ${YELLOW}gula agent login${NC}"
            fi
        fi
    else
        echo -e "Estado: ${RED}No autenticado${NC}"
        echo -e "Ejecuta: ${YELLOW}gula agent login${NC}"
    fi
}

# Validate if the current token is still valid
validate_agent_token() {
    local api_url=$(get_agent_config "api_url")
    local access_token=$(get_agent_config "access_token")

    if [ -z "$access_token" ] || [ "$access_token" = "None" ] || [ "$access_token" = "null" ]; then
        return 1
    fi

    # Make a test request to check token validity
    local response=$(curl -s -w "\n%{http_code}" "$api_url/agent/conversations" \
        -H "Authorization: Bearer $access_token" 2>/dev/null)

    local http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
        return 1
    fi

    return 0
}

# Refresh the access token using the refresh token
refresh_agent_token() {
    local api_url=$(get_agent_config "api_url")
    local refresh_token=$(get_agent_config "refresh_token")

    if [ -z "$refresh_token" ] || [ "$refresh_token" = "None" ] || [ "$refresh_token" = "null" ]; then
        return 1
    fi

    # Call refresh endpoint
    local response=$(curl -s -X POST "$api_url/users/refresh" \
        -H "Content-Type: application/json" \
        -d "{\"refresh_token\": \"$refresh_token\"}" 2>/dev/null)

    # Check if we got new tokens
    local new_access_token=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null)
    local new_refresh_token=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token', ''))" 2>/dev/null)

    if [ -n "$new_access_token" ] && [ "$new_access_token" != "null" ] && [ "$new_access_token" != "" ]; then
        # Save new tokens
        set_agent_config "access_token" "$new_access_token"
        if [ -n "$new_refresh_token" ] && [ "$new_refresh_token" != "null" ]; then
            set_agent_config "refresh_token" "$new_refresh_token"
        fi
        return 0
    fi

    return 1
}

# Ensure we have a valid token, trying refresh first
ensure_valid_token_with_refresh() {
    # First check if we have any token
    if ! is_agent_authenticated; then
        return 1
    fi

    # Check if current token is valid
    if validate_agent_token; then
        return 0
    fi

    # Token expired, try to refresh silently
    echo -e "  ${DIM}Renovando sesion...${NC}" >&2
    if refresh_agent_token; then
        echo -e "  ${GREEN}✓${NC} Sesion renovada" >&2
        return 0
    fi

    # Refresh failed, token is truly expired
    return 1
}

# Check token and prompt for re-login if expired
ensure_valid_token() {
    if ! is_agent_authenticated; then
        return 1
    fi

    if ! validate_agent_token; then
        echo -e "${YELLOW}Tu sesion ha expirado.${NC}"
        echo ""

        # Clear expired tokens
        set_agent_config "access_token" "null"
        set_agent_config "refresh_token" "null"

        read -p "Deseas iniciar sesion de nuevo? (s/n): " relogin
        if [[ "$relogin" =~ ^[sS]$ ]]; then
            echo ""
            if agent_login; then
                return 0
            fi
        fi
        return 1
    fi

    return 0
}

# Check API response for auth errors
check_api_response() {
    local response="$1"

    # Check for common auth error patterns
    local error_detail=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    detail = data.get('detail', '')
    if isinstance(detail, str):
        print(detail)
    elif isinstance(detail, dict):
        print(detail.get('message', ''))
except:
    pass
" 2>/dev/null)

    if [[ "$error_detail" == *"token"* ]] || [[ "$error_detail" == *"expired"* ]] || \
       [[ "$error_detail" == *"invalid"* ]] || [[ "$error_detail" == *"authentication"* ]] || \
       [[ "$error_detail" == *"Not authenticated"* ]]; then
        echo "auth_error"
        return 1
    fi

    # Check for empty response or connection error
    if [ -z "$response" ]; then
        echo "empty_response"
        return 1
    fi

    echo "ok"
    return 0
}

# Send a single message and get response (non-streaming)
send_chat_message() {
    local prompt="$1"
    local conversation_id="$2"
    local max_iterations="${3:-10}"
    local api_url=$(get_agent_config "api_url")
    local access_token=$(get_agent_config "access_token")

    local endpoint="$api_url/agent/chat"
    # Escape special characters in prompt for JSON
    local escaped_prompt=$(echo "$prompt" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
    local payload="{\"prompt\": $escaped_prompt, \"max_iterations\": $max_iterations}"

    if [ -n "$conversation_id" ]; then
        endpoint="$api_url/agent/conversations/$conversation_id/messages"
    fi

    local response=$(curl -s -X POST "$endpoint" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $access_token" \
        -d "$payload")

    echo "$response"
}

# Send message with SSE streaming - displays events in real-time
# Returns JSON result via stdout
send_chat_message_streaming() {
    local prompt="$1"
    local conversation_id="$2"
    local max_iterations="${3:-10}"
    local api_url=$(get_agent_config "api_url")
    local access_token=$(get_agent_config "access_token")

    local endpoint="$api_url/agent/chat/stream"

    if [ -n "$conversation_id" ]; then
        endpoint="$api_url/agent/conversations/$conversation_id/messages/stream"
    fi

    # Guardar prompt en archivo temporal
    local tmp_prompt=$(mktemp)
    echo "$prompt" > "$tmp_prompt"

    # Use Python to handle SSE parsing and display
    python3 - "$tmp_prompt" "$endpoint" "$access_token" "$max_iterations" << 'PYEOF'
import sys
import json
import subprocess
import os

# Colors
YELLOW = "\033[1;33m"
GREEN = "\033[1;32m"
BOLD = "\033[1m"
NC = "\033[0m"

tmp_prompt = sys.argv[1]
endpoint = sys.argv[2]
access_token = sys.argv[3]
max_iterations = int(sys.argv[4])

# Leer prompt
with open(tmp_prompt) as f:
    prompt = f.read().strip()
os.unlink(tmp_prompt)

# Escape prompt for JSON
payload = json.dumps({"prompt": prompt, "max_iterations": max_iterations})

# Run curl and process stream
proc = subprocess.Popen(
    ["curl", "-s", "-N", "-X", "POST", endpoint,
     "-H", "Content-Type: application/json",
     "-H", f"Authorization: Bearer {access_token}",
     "-d", payload],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

event_type = None
texts = []
result = {
    "conversation_id": None,
    "total_cost": 0,
    "max_iterations_reached": False,
    "response": "",
    "error": None
}

for line in proc.stdout:
    line = line.strip()

    if line.startswith("event:"):
        event_type = line[7:].strip()
        continue

    if line.startswith("data:"):
        data = line[6:].strip()
        try:
            parsed = json.loads(data)
        except:
            continue

        if event_type == "started":
            result["conversation_id"] = parsed.get("conversation_id")

        elif event_type == "thinking":
            it = parsed.get("iteration", 1)
            mx = parsed.get("max_iterations", 10)
            print(f"  {YELLOW}[Iteracion {it}/{mx}] Pensando...{NC}", file=sys.stderr)

        elif event_type == "tool_call":
            tool = parsed.get("tool", "")
            inp = parsed.get("input", {})
            preview = inp.get("command", inp.get("file_path", inp.get("path", str(inp)[:60])))
            print(f"  {BOLD}[Tool] {tool}{NC}: {preview}", file=sys.stderr)

        elif event_type == "tool_result":
            tool = parsed.get("tool", "")
            res = parsed.get("result", "")
            preview = res[:100].replace("\n", " ")
            if len(res) > 100:
                preview += "..."
            print(f"  {GREEN}[Resultado]{NC}: {preview}", file=sys.stderr)

        elif event_type == "text":
            content = parsed.get("content", "")
            if content:
                texts.append(content)

        elif event_type == "complete":
            result["conversation_id"] = parsed.get("conversation_id")
            result["total_cost"] = parsed.get("total_cost", 0)
            result["max_iterations_reached"] = parsed.get("max_iterations_reached", False)

        elif event_type == "error":
            result["error"] = parsed.get("error", "Unknown error")

proc.wait()

# Combine all text responses
result["response"] = "\n".join(texts) if texts else ""

# Output result as JSON
print(json.dumps(result))
PYEOF
}

# ============================================================================
# CHAT HIBRIDO - Tools se ejecutan localmente
# ============================================================================

# Envia chat hibrido con ejecucion local de tools
# El servidor envia tool_requests, el cliente los ejecuta y envia resultados
send_chat_hybrid() {
    local prompt="$1"
    local conversation_id="$2"
    local tool_results_json="$3"  # JSON array de tool results o vacio
    local max_iterations="${4:-10}"

    local api_url=$(get_agent_config "api_url")
    local access_token=$(get_agent_config "access_token")
    local endpoint="$api_url/agent/chat/hybrid"

    # Generar contexto del proyecto solo en el primer mensaje
    local project_context=""
    if [ -z "$conversation_id" ] && [ -z "$tool_results_json" ]; then
        project_context=$(generate_project_context)
    fi

    # Guardar datos en archivos temporales para evitar problemas de escape
    local tmp_prompt=$(mktemp)
    local tmp_context=$(mktemp)
    local tmp_results=$(mktemp)
    echo "$prompt" > "$tmp_prompt"
    echo "$project_context" > "$tmp_context"
    echo "$tool_results_json" > "$tmp_results"

    # Construir payload con Python
    local payload=$(python3 - "$tmp_prompt" "$tmp_context" "$tmp_results" "$conversation_id" "$max_iterations" << 'PYEOF'
import json
import sys

tmp_prompt = sys.argv[1]
tmp_context = sys.argv[2]
tmp_results = sys.argv[3]
conv_id = sys.argv[4]
max_iter = int(sys.argv[5])

data = {"max_iterations": max_iter}

# Leer prompt
with open(tmp_prompt) as f:
    prompt = f.read().strip()
if prompt:
    data["prompt"] = prompt

# Agregar conversation_id si existe
if conv_id:
    data["conversation_id"] = int(conv_id)

# Leer contexto del proyecto
with open(tmp_context) as f:
    project_ctx = f.read().strip()
if project_ctx:
    try:
        data["project_context"] = json.loads(project_ctx)
    except:
        pass

# Leer tool_results
with open(tmp_results) as f:
    tool_results = f.read().strip()
if tool_results:
    try:
        data["tool_results"] = json.loads(tool_results)
    except:
        pass

print(json.dumps(data))
PYEOF
)
    rm -f "$tmp_prompt" "$tmp_context" "$tmp_results"

    # Guardar payload en archivo temporal
    local tmp_payload=$(mktemp)
    echo "$payload" > "$tmp_payload"

    # Llamar al endpoint y procesar SSE con UI mejorada
    python3 - "$endpoint" "$access_token" "$tmp_payload" << 'PYEOF'
import sys
import json
import subprocess
import time
import threading

# ============================================================================
# UI Configuration
# ============================================================================

# Colors
BOLD = "\033[1m"
DIM = "\033[2m"
NC = "\033[0m"
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
CYAN = "\033[0;36m"

# Cursor control
HIDE_CURSOR = "\033[?25l"
SHOW_CURSOR = "\033[?25h"
CLEAR_LINE = "\033[2K"
CURSOR_START = "\r"

# Spinner frames
SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

# Tool icons
TOOL_ICONS = {
    "read_file": "📖",
    "write_file": "✏️ ",
    "list_files": "📁",
    "search_code": "🔍",
    "run_command": "⌘ ",
    "git_info": "🔀",
}

# ============================================================================
# Spinner class
# ============================================================================

class Spinner:
    def __init__(self):
        self.running = False
        self.message = ""
        self.thread = None
        self.frame = 0
        self.start_time = None

    def start(self, message=""):
        self.message = message
        self.running = True
        self.start_time = time.time()
        self.frame = 0
        sys.stderr.write(HIDE_CURSOR)
        self.thread = threading.Thread(target=self._spin, daemon=True)
        self.thread.start()

    def _spin(self):
        while self.running:
            frame = SPINNER[self.frame % len(SPINNER)]
            elapsed = time.time() - self.start_time
            line = f"{CURSOR_START}{CLEAR_LINE}  {CYAN}{frame}{NC} {self.message} {DIM}({elapsed:.1f}s){NC}"
            sys.stderr.write(line)
            sys.stderr.flush()
            self.frame += 1
            time.sleep(0.08)

    def update(self, message):
        self.message = message

    def stop(self, final_message=None, status="success"):
        self.running = False
        if self.thread:
            self.thread.join(timeout=0.2)

        sys.stderr.write(f"{CURSOR_START}{CLEAR_LINE}{SHOW_CURSOR}")

        if final_message:
            elapsed = time.time() - self.start_time if self.start_time else 0
            if status == "success":
                icon = f"{GREEN}✓{NC}"
            elif status == "error":
                icon = f"{RED}✗{NC}"
            else:
                icon = f"{CYAN}ℹ{NC}"
            sys.stderr.write(f"  {icon} {final_message} {DIM}({elapsed:.1f}s){NC}\n")

        sys.stderr.flush()

# ============================================================================
# Main processing
# ============================================================================

endpoint = sys.argv[1]
access_token = sys.argv[2]
tmp_payload = sys.argv[3]

with open(tmp_payload) as f:
    payload = f.read().strip()

# Initialize
spinner = Spinner()
start_time = time.time()
tools_executed = 0

# Run curl and process stream
proc = subprocess.Popen(
    ["curl", "-s", "-N", "-X", "POST", endpoint,
     "-H", "Content-Type: application/json",
     "-H", f"Authorization: Bearer {access_token}",
     "-d", payload],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

event_type = None
texts = []
result = {
    "conversation_id": None,
    "total_cost": 0,
    "total_tokens": 0,
    "max_iterations_reached": False,
    "response": "",
    "error": None,
    "tool_requests": None,
    "elapsed_time": 0,
    "tools_count": 0
}

try:
    for line in proc.stdout:
        line = line.strip()

        if line.startswith("event:"):
            event_type = line[7:].strip()
            continue

        if line.startswith("data:"):
            data = line[6:].strip()
            try:
                parsed = json.loads(data)
            except:
                continue

            if event_type == "started":
                result["conversation_id"] = parsed.get("conversation_id")
                conv_id = parsed.get("conversation_id")
                spinner.start(f"Conectado a conversacion #{conv_id}")

            elif event_type == "thinking":
                it = parsed.get("iteration", 1)
                mx = parsed.get("max_iterations", 10)
                spinner.update(f"Pensando... {DIM}(iteracion {it}/{mx}){NC}")

            elif event_type == "text":
                content = parsed.get("content", "")
                if content:
                    texts.append(content)
                    # Show brief preview in spinner
                    preview = content[:40].replace("\n", " ")
                    if len(content) > 40:
                        preview += "..."
                    spinner.update(f"Generando respuesta...")

            elif event_type == "tool_requests":
                spinner.stop(f"Servidor solicita {len(parsed.get('tool_calls', []))} herramienta(s)", "info")
                result["tool_requests"] = parsed.get("tool_calls", [])
                result["conversation_id"] = parsed.get("conversation_id")
                tools_executed = len(result["tool_requests"])

            elif event_type == "complete":
                result["conversation_id"] = parsed.get("conversation_id")
                result["total_cost"] = parsed.get("total_cost", 0)
                result["total_tokens"] = parsed.get("total_input_tokens", 0) + parsed.get("total_output_tokens", 0)
                result["max_iterations_reached"] = parsed.get("max_iterations_reached", False)
                spinner.stop("Completado", "success")

            elif event_type == "error":
                result["error"] = parsed.get("error", "Unknown error")
                spinner.stop(f"Error: {result['error']}", "error")

except KeyboardInterrupt:
    spinner.stop("Cancelado", "error")
    proc.terminate()
finally:
    # Ensure spinner is stopped
    if spinner.running:
        spinner.stop()

proc.wait()

# Calculate elapsed time
result["elapsed_time"] = round(time.time() - start_time, 2)
result["tools_count"] = tools_executed

# Combine all text responses
result["response"] = "\n".join(texts) if texts else ""

# Cleanup and output
import os
os.unlink(tmp_payload)
print(json.dumps(result))
PYEOF
}

# Loop completo de chat hibrido con ejecucion local de tools
run_hybrid_chat() {
    local prompt="$1"
    local conversation_id="$2"
    local max_iterations="${3:-10}"

    local current_conv_id="$conversation_id"
    local tool_results=""
    local iteration=0
    local max_tool_iterations=20  # Limite de seguridad

    while [ $iteration -lt $max_tool_iterations ]; do
        iteration=$((iteration + 1))

        # Llamar al servidor
        local response
        if [ $iteration -eq 1 ]; then
            # Primera llamada: enviar prompt
            response=$(send_chat_hybrid "$prompt" "$current_conv_id" "" "$max_iterations")
        else
            # Llamadas siguientes: enviar tool_results
            response=$(send_chat_hybrid "" "$current_conv_id" "$tool_results" "$max_iterations")
        fi

        # Verificar error
        local error=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error') or '')" 2>/dev/null)
        if [ -n "$error" ]; then
            # Check if it's an auth error
            if [[ "$error" == *"Not authenticated"* ]] || [[ "$error" == *"token"* ]] || \
               [[ "$error" == *"expired"* ]] || [[ "$error" == *"401"* ]] || \
               [[ "$error" == *"authentication"* ]] || [[ "$error" == *"unauthorized"* ]]; then
                echo '{"error": "auth_expired", "message": "Tu sesion ha expirado"}'
                return 2  # Special return code for auth errors
            fi
            echo "$response"
            return 1
        fi

        # Obtener conversation_id
        current_conv_id=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('conversation_id') or '')" 2>/dev/null)

        # Verificar si hay tool_requests
        local tool_requests=$(echo "$response" | python3 -c "import sys,json; r=json.load(sys.stdin).get('tool_requests'); print(json.dumps(r) if r else '')" 2>/dev/null)

        if [ -n "$tool_requests" ] && [ "$tool_requests" != "null" ]; then
            # Guardar tool_requests en archivo temporal para evitar problemas de escape
            local tmp_requests=$(mktemp)
            echo "$tool_requests" > "$tmp_requests"

            tool_results=$(python3 - "$tmp_requests" "$AGENT_SCRIPT_DIR" << 'PYEOF'
import json
import subprocess
import sys
import os
import time
import threading

# ============================================================================
# UI Configuration
# ============================================================================

BOLD = "\033[1m"
DIM = "\033[2m"
NC = "\033[0m"
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
CYAN = "\033[0;36m"

HIDE_CURSOR = "\033[?25l"
SHOW_CURSOR = "\033[?25h"
CLEAR_LINE = "\033[2K"
CURSOR_START = "\r"

SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

TOOL_ICONS = {
    "read_file": "📖",
    "write_file": "✏️",
    "list_files": "📁",
    "search_code": "🔍",
    "run_command": "⌘",
    "git_info": "🔀",
}

# ============================================================================
# Spinner for tool execution
# ============================================================================

class ToolSpinner:
    def __init__(self):
        self.running = False
        self.message = ""
        self.thread = None
        self.frame = 0
        self.start_time = None

    def start(self, message=""):
        self.message = message
        self.running = True
        self.start_time = time.time()
        self.frame = 0
        sys.stderr.write(HIDE_CURSOR)
        self.thread = threading.Thread(target=self._spin, daemon=True)
        self.thread.start()

    def _spin(self):
        while self.running:
            frame = SPINNER[self.frame % len(SPINNER)]
            elapsed = time.time() - self.start_time
            line = f"{CURSOR_START}{CLEAR_LINE}    {CYAN}{frame}{NC} {self.message} {DIM}({elapsed:.1f}s){NC}"
            sys.stderr.write(line)
            sys.stderr.flush()
            self.frame += 1
            time.sleep(0.08)

    def stop(self):
        self.running = False
        if self.thread:
            self.thread.join(timeout=0.2)
        sys.stderr.write(f"{CURSOR_START}{CLEAR_LINE}{SHOW_CURSOR}")
        sys.stderr.flush()
        return time.time() - self.start_time if self.start_time else 0

# ============================================================================
# Main processing
# ============================================================================

tmp_file = sys.argv[1]
agent_script_dir = sys.argv[2]

with open(tmp_file) as f:
    tool_requests = json.load(f)

results = []
total_tools = len(tool_requests)

# Header
sys.stderr.write(f"\n  {BOLD}Ejecutando {total_tools} herramienta(s) localmente{NC}\n")
sys.stderr.flush()

for idx, tc in enumerate(tool_requests, 1):
    tc_id = tc["id"]
    tc_name = tc["name"]
    tc_input = tc["input"]

    # Get icon and format detail
    icon = TOOL_ICONS.get(tc_name, "⚡")

    # Format the detail based on tool type
    if tc_name == "read_file":
        detail = tc_input.get("path", "")
    elif tc_name == "write_file":
        detail = tc_input.get("path", "")
    elif tc_name == "list_files":
        detail = tc_input.get("path", ".") + "/" + tc_input.get("pattern", "*")
    elif tc_name == "search_code":
        detail = f'"{tc_input.get("query", "")}"'
    elif tc_name == "run_command":
        cmd = tc_input.get("command", "")
        detail = cmd[:40] + "..." if len(cmd) > 40 else cmd
    elif tc_name == "git_info":
        detail = tc_input.get("type", "status")
    else:
        detail = str(tc_input)[:40]

    # Print tool header
    sys.stderr.write(f"  {icon} {BOLD}{tc_name}{NC} {DIM}{detail}{NC}\n")
    sys.stderr.flush()

    # Start spinner
    spinner = ToolSpinner()
    spinner.start("Ejecutando...")

    # Write input to temp file
    import tempfile
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as tf:
        tf.write(json.dumps(tc_input))
        input_file = tf.name

    try:
        cmd = f'source "{agent_script_dir}/agent_local_tools.sh" && execute_tool_locally "{tc_name}" "$(cat {input_file})"'
        result = subprocess.run(
            ["bash", "-c", cmd],
            capture_output=True,
            text=True,
            timeout=60,
            env={**os.environ, "AGENT_SCRIPT_DIR": agent_script_dir}
        )
        output = result.stdout or result.stderr or "Sin resultado"
        success = result.returncode == 0 and not output.startswith("Error:")
    except subprocess.TimeoutExpired:
        output = "Error: Timeout ejecutando tool (60s)"
        success = False
    except Exception as e:
        output = f"Error: {str(e)}"
        success = False
    finally:
        os.unlink(input_file)

    # Stop spinner
    elapsed = spinner.stop()

    # Truncate long output
    if len(output) > 10000:
        output = output[:10000] + "\n... [truncado]"

    # Format preview
    preview = output[:60].replace("\n", " ").strip()
    if len(output) > 60:
        preview += "..."

    # Print result
    if success:
        sys.stderr.write(f"    {GREEN}✓{NC} {DIM}{preview}{NC} {DIM}({elapsed:.1f}s){NC}\n")
    else:
        sys.stderr.write(f"    {RED}✗{NC} {preview} {DIM}({elapsed:.1f}s){NC}\n")
    sys.stderr.flush()

    results.append({
        "tool_call_id": tc_id,
        "tool_name": tc_name,
        "result": output
    })

# Summary line
sys.stderr.write(f"\n")
sys.stderr.flush()

print(json.dumps(results))
PYEOF
)
            rm -f "$tmp_requests"
            # Continuar el loop para enviar resultados
            continue
        fi

        # No hay tool_requests, devolver respuesta final
        echo "$response"
        return 0
    done

    echo '{"error": "Maximo de iteraciones de tools alcanzado"}'
    return 1
}

# Agent chat - single message or interactive mode
agent_chat() {
    init_agent_config

    # Check dependencies on first run
    if ! ensure_agent_dependencies; then
        return 1
    fi

    # Verify authentication and token validity (with auto-refresh)
    if is_agent_authenticated; then
        # Have a token, try to ensure it's valid (will refresh if needed)
        if ! ensure_valid_token_with_refresh; then
            echo -e "${YELLOW}Tu sesion ha expirado y no se pudo renovar.${NC}"
            echo ""
            # Clear expired tokens
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

    # Single message mode with hybrid execution
    echo -e "${BOLD}Analizando proyecto y enviando mensaje...${NC}"
    show_project_info
    echo ""

    local response
    response=$(run_hybrid_chat "$prompt" "")
    local run_status=$?

    # Handle auth errors - try refresh first, then prompt for login
    if [ $run_status -eq 2 ]; then
        echo -e "  ${DIM}Sesion expirada, intentando renovar...${NC}"
        if refresh_agent_token; then
            echo -e "  ${GREEN}✓${NC} Sesion renovada"
            echo ""
            echo -e "${BOLD}Reintentando...${NC}"
            response=$(run_hybrid_chat "$prompt" "")
            run_status=$?
        else
            echo -e "${YELLOW}No se pudo renovar la sesion.${NC}"
            echo ""
            read -p "Deseas iniciar sesion de nuevo? (s/n): " relogin
            if [[ "$relogin" =~ ^[sS]$ ]]; then
                echo ""
                set_agent_config "access_token" "null"
                set_agent_config "refresh_token" "null"
                if agent_login; then
                    echo ""
                    echo -e "${BOLD}Reintentando...${NC}"
                    response=$(run_hybrid_chat "$prompt" "")
                    run_status=$?
                else
                    echo -e "${RED}No se pudo iniciar sesion.${NC}"
                    return 1
                fi
            else
                return 1
            fi
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

    # Display response header
    echo ""
    echo -e "${BOLD}${YELLOW}Agent:${NC}"
    echo ""

    # Render markdown with glow if available
    if command -v glow &> /dev/null; then
        echo "$text_response" | glow -s dark -w 80 -
    else
        echo "$text_response"
    fi

    # Display summary
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
    echo -e "  ${DIM}Conversacion:${NC} #$conv_id"
    echo -e "${DIM}───────────────────────────────────────────────────${NC}"
}

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

        # Send message with continuation loop (using hybrid mode)
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
                echo -e "  ${DIM}Sesion expirada, intentando renovar...${NC}"
                if refresh_agent_token; then
                    echo -e "  ${GREEN}✓${NC} Sesion renovada"
                    echo ""
                    response=$(run_hybrid_chat "$current_prompt" "$conversation_id")
                    run_status=$?
                else
                    echo -e "${YELLOW}No se pudo renovar la sesion.${NC}"
                    echo ""
                    read -p "Deseas iniciar sesion de nuevo? (s/n): " relogin
                    if [[ "$relogin" =~ ^[sS]$ ]]; then
                        echo ""
                        set_agent_config "access_token" "null"
                        set_agent_config "refresh_token" "null"
                        if agent_login; then
                            echo ""
                            echo -e "${BOLD}Reintentando...${NC}"
                            response=$(run_hybrid_chat "$current_prompt" "$conversation_id")
                            run_status=$?
                        else
                            echo -e "${RED}No se pudo iniciar sesion.${NC}"
                            break
                        fi
                    else
                        break
                    fi
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

            # Display response with markdown rendering
            echo ""
            echo -e "${BOLD}${YELLOW}Agent:${NC}"
            echo ""
            # Try glow for markdown rendering, fallback to simple conversion
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
                    # Continue with a follow-up prompt
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
            echo -e "${YELLOW}Tu sesion ha expirado.${NC}"
            echo ""
            read -p "Deseas iniciar sesion de nuevo? (s/n): " relogin
            if [[ "$relogin" =~ ^[sS]$ ]]; then
                set_agent_config "access_token" "null"
                set_agent_config "refresh_token" "null"
                if agent_login; then
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
                    echo -e "${RED}No se pudo iniciar sesion.${NC}"
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

# Show agent help
show_agent_help() {
    echo ""
    echo -e "${BOLD}===============================================${NC}"
    echo -e "${BOLD}           GULA AGENT - AYUDA                  ${NC}"
    echo -e "${BOLD}===============================================${NC}"
    echo ""
    echo -e "${BOLD}DESCRIPCION:${NC}"
    echo "  Interactua con el servidor de agentes AI desde la linea de comandos."
    echo ""
    echo -e "${BOLD}COMANDOS:${NC}"
    echo ""
    echo -e "  ${BOLD}gula agent setup${NC}"
    echo "      Instala las dependencias necesarias (glow, etc.)"
    echo ""
    echo -e "  ${BOLD}gula agent login${NC}"
    echo "      Inicia sesion abriendo el navegador para autenticacion"
    echo ""
    echo -e "  ${BOLD}gula agent logout${NC}"
    echo "      Cierra la sesion actual"
    echo ""
    echo -e "  ${BOLD}gula agent status${NC}"
    echo "      Muestra el estado de autenticacion"
    echo ""
    echo -e "  ${BOLD}gula agent chat${NC}"
    echo "      Inicia modo interactivo (como Claude Code)"
    echo "      Comandos en modo interactivo:"
    echo "        /exit, /quit, /q  - Salir del chat"
    echo "        /new              - Nueva conversacion"
    echo "        /cost             - Ver costo acumulado"
    echo "        /clear            - Limpiar pantalla"
    echo "        /help             - Mostrar ayuda"
    echo ""
    echo -e "  ${BOLD}gula agent chat \"mensaje\"${NC}"
    echo "      Envia un mensaje unico al agente AI"
    echo ""
    echo -e "  ${BOLD}gula agent project${NC}"
    echo "      Muestra informacion del proyecto actual"
    echo ""
    echo -e "  ${BOLD}gula agent context${NC}"
    echo "      Muestra el contexto JSON que se envia al servidor"
    echo ""
    echo -e "  ${BOLD}gula agent conversations${NC}"
    echo "      Lista todas las conversaciones"
    echo ""
    echo -e "  ${BOLD}gula agent --help${NC}"
    echo "      Muestra esta ayuda"
    echo ""
    echo -e "${BOLD}EJEMPLOS:${NC}"
    echo ""
    echo "  gula agent setup              # Instalar dependencias"
    echo "  gula agent login              # Iniciar sesion"
    echo "  gula agent chat               # Modo interactivo"
    echo "  gula agent chat \"Hola\"        # Mensaje unico"
    echo "  gula agent conversations      # Ver historial"
    echo ""
    echo -e "${BOLD}DEPENDENCIAS:${NC}"
    echo ""
    echo "  Requeridas: python3, curl"
    echo "  Opcionales: glow (renderizado de Markdown)"
    echo ""
    echo -e "${BOLD}CONFIGURACION:${NC}"
    echo ""
    echo "  Los tokens se guardan en: ~/.config/gula-agent/config.json"
    echo "  Para cambiar la URL del servidor, edita el archivo de configuracion"
    echo "  o usa la variable de entorno AGENT_API_URL"
    echo ""
    echo -e "${BOLD}===============================================${NC}"
}

# Main agent command dispatcher
agent_command() {
    local subcommand="${1:-help}"
    shift 2>/dev/null || true

    case "$subcommand" in
        setup)
            # Check for --reset flag
            if [[ "$1" == "--reset" ]]; then
                rm -f "$AGENT_SETUP_DONE_FILE"
                echo -e "${YELLOW}Setup reseteado. Ejecutando instalacion...${NC}"
                echo ""
            fi
            install_agent_dependencies
            ;;
        login)
            agent_login
            ;;
        logout)
            agent_logout
            ;;
        status)
            agent_status
            ;;
        chat)
            agent_chat "$@"
            ;;
        project)
            show_project_info
            ;;
        context)
            # Mostrar contexto JSON que se enviaria al servidor
            generate_project_context | python3 -m json.tool
            ;;
        conversations|conv)
            agent_conversations
            ;;
        help|--help|-h)
            show_agent_help
            ;;
        *)
            echo -e "${RED}Comando desconocido: $subcommand${NC}"
            echo -e "Usa ${YELLOW}gula agent help${NC} para ver los comandos disponibles"
            return 1
            ;;
    esac
}
