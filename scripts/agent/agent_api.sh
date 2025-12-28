#!/bin/bash

# Agent API Module
# Handles communication with the server (SSE, hybrid chat)

# ============================================================================
# HYBRID CHAT API
# ============================================================================

# Send hybrid chat request and process SSE response
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

# ============================================================================
# LOCAL TOOL EXECUTION
# ============================================================================

# Execute tools locally and return results
execute_tools_locally() {
    local tool_requests="$1"

    # Guardar tool_requests en archivo temporal
    local tmp_requests=$(mktemp)
    echo "$tool_requests" > "$tmp_requests"

    python3 - "$tmp_requests" "$AGENT_SCRIPT_DIR" << 'PYEOF'
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

    rm -f "$tmp_requests"
}

# ============================================================================
# HYBRID CHAT LOOP
# ============================================================================

# Complete hybrid chat loop with local tool execution
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
            # Ejecutar tools localmente
            tool_results=$(execute_tools_locally "$tool_requests")
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
