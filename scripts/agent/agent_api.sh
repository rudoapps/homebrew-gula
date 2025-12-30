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
    local subagent_id="${5:-}"    # Optional: ID del subagente a usar
    local images_json="${6:-}"    # Optional: JSON array de imagenes

    local api_url=$(get_agent_config "api_url")
    local access_token=$(get_agent_config "access_token")
    local endpoint="$api_url/agent/chat/hybrid"

    # Generar contexto del proyecto solo en el primer mensaje
    local project_context=""
    local git_remote_url=""
    if [ -z "$conversation_id" ] && [ -z "$tool_results_json" ]; then
        project_context=$(generate_project_context)
    fi

    # Get git remote URL for RAG context - always send with new prompts (not tool_results)
    if [ -z "$tool_results_json" ] && [ -n "$prompt" ]; then
        git_remote_url=$(get_rag_git_url 2>/dev/null || echo "")
    fi

    # Guardar datos en archivos temporales para evitar problemas de escape
    local tmp_prompt=$(mktemp)
    local tmp_context=$(mktemp)
    local tmp_results=$(mktemp)
    local tmp_subagent=$(mktemp)
    local tmp_git_url=$(mktemp)
    local tmp_images=$(mktemp)
    echo "$prompt" > "$tmp_prompt"
    echo "$project_context" > "$tmp_context"
    echo "$tool_results_json" > "$tmp_results"
    echo "$subagent_id" > "$tmp_subagent"
    echo "$git_remote_url" > "$tmp_git_url"
    echo "$images_json" > "$tmp_images"

    # Construir payload con Python
    local payload=$(python3 - "$tmp_prompt" "$tmp_context" "$tmp_results" "$conversation_id" "$max_iterations" "$tmp_subagent" "$tmp_git_url" "$tmp_images" << 'PYEOF'
import json
import sys

try:
    tmp_prompt = sys.argv[1]
    tmp_context = sys.argv[2]
    tmp_results = sys.argv[3]
    conv_id = sys.argv[4]
    max_iter_str = sys.argv[5]
    tmp_subagent = sys.argv[6]
    tmp_git_url = sys.argv[7]
    tmp_images = sys.argv[8] if len(sys.argv) > 8 else None

    # Parse max_iterations with fallback
    try:
        max_iter = int(max_iter_str) if max_iter_str else 10
    except ValueError:
        max_iter = 10

    data = {"max_iterations": max_iter}

    # Leer prompt
    with open(tmp_prompt) as f:
        prompt = f.read().strip()
    if prompt:
        data["prompt"] = prompt

    # Agregar conversation_id si existe
    if conv_id:
        try:
            data["conversation_id"] = int(conv_id)
        except ValueError:
            pass  # Skip invalid conversation_id

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
            parsed_results = json.loads(tool_results)
            if parsed_results:  # Only add if not empty
                data["tool_results"] = parsed_results
        except json.JSONDecodeError as e:
            # Log error but continue - this is the critical fix
            print(f"Warning: Failed to parse tool_results: {e}", file=sys.stderr)

    # Leer subagent_id
    with open(tmp_subagent) as f:
        subagent_id = f.read().strip()
    if subagent_id:
        data["subagent_id"] = subagent_id

    # Leer git_remote_url para RAG
    with open(tmp_git_url) as f:
        git_url = f.read().strip()
    if git_url:
        data["git_remote_url"] = git_url

    # Leer imagenes
    if tmp_images:
        with open(tmp_images) as f:
            images_str = f.read().strip()
        if images_str:
            try:
                images = json.loads(images_str)
                if images and isinstance(images, list) and len(images) > 0:
                    # Remove source_path (internal only) before sending
                    for img in images:
                        img.pop('source_path', None)
                    data["images"] = images
            except:
                pass

    # Ensure we always output valid JSON
    print(json.dumps(data))

except Exception as e:
    # Fallback: output minimal valid payload to prevent 422 errors
    print(f"Error building payload: {e}", file=sys.stderr)
    fallback = {"max_iterations": 10, "error": str(e)}
    print(json.dumps(fallback))
PYEOF
)
    rm -f "$tmp_prompt" "$tmp_context" "$tmp_results" "$tmp_subagent" "$tmp_git_url" "$tmp_images"

    # Validate payload is not empty
    if [ -z "$payload" ]; then
        echo '{"error": "Failed to build request payload", "response": ""}'
        return 1
    fi

    # Validate payload has either prompt or tool_results (required by server)
    local has_content=$(echo "$payload" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if d.get('prompt') or d.get('tool_results') else 'no')" 2>/dev/null)
    if [ "$has_content" != "yes" ]; then
        echo '{"error": "Request must have either prompt or tool_results", "response": ""}'
        return 1
    fi

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
# Markdown to ANSI converter
# ============================================================================

import re

def markdown_to_ansi(text):
    """Convert basic markdown to ANSI terminal codes."""

    # Code blocks (```lang ... ``` or `` ... ``) - handle 2+ backticks
    def replace_code_block(match):
        code = match.group(2) or match.group(0)
        return f"{DIM}{code}{NC}"
    text = re.sub(r'`{2,}(\w*)\n?(.*?)`{2,}', replace_code_block, text, flags=re.DOTALL)

    # Inline code (`code`) - dim - but not if already processed
    text = re.sub(r'(?<!`)`([^`\n]+)`(?!`)', f'{DIM}\\1{NC}', text)

    # Headers with ## syntax - bold + color
    text = re.sub(r'^####\s*(.+)$', f'{BOLD}{BLUE}\\1{NC}', text, flags=re.MULTILINE)
    text = re.sub(r'^###\s*(.+)$', f'{BOLD}{CYAN}\\1{NC}', text, flags=re.MULTILINE)
    text = re.sub(r'^##\s*(.+)$', f'{BOLD}{YELLOW}\\1{NC}', text, flags=re.MULTILINE)
    text = re.sub(r'^#\s*(.+)$', f'{BOLD}{GREEN}\\1{NC}', text, flags=re.MULTILINE)

    # Lines starting with emoji (likely headers) - make bold
    text = re.sub(r'^([🏦🏗️⚡🔑🔄🛡️🎨🔗🎯✅❌📊📋📁💳💾👤🔐💰📱🧠💾]+ .+)$', f'{BOLD}\\1{NC}', text, flags=re.MULTILINE)

    # Bold (**text** or __text__) - bold
    text = re.sub(r'\*\*([^*]+)\*\*', f'{BOLD}\\1{NC}', text)
    text = re.sub(r'__([^_]+)__', f'{BOLD}\\1{NC}', text)

    # Bullet points (- item or • item) - add color to bullet
    text = re.sub(r'^(\s*)[-•] (.+)$', f'\\1{CYAN}•{NC} \\2', text, flags=re.MULTILINE)

    # Horizontal rules (---) - dim line
    text = re.sub(r'^-{3,}$', f'{DIM}───────────────────────────────{NC}', text, flags=re.MULTILINE)

    # Tables - just leave as-is but dim the pipes
    text = re.sub(r'\|', f'{DIM}|{NC}', text)

    return text

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

# Start spinner immediately (before curl connects)
spinner.start("Conectando con el servidor...")

# Run curl and process stream
proc = subprocess.Popen(
    ["curl", "-s", "-N", "-X", "POST", endpoint,
     "-H", "Content-Type: application/json",
     "-H", f"Authorization: Bearer {access_token}",
     "-d", payload],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1  # Line buffered for real-time output
)

event_type = None
texts = []
streaming_text = False  # Track if we're in text streaming mode
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
    first_line = True
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue

        # Check for HTTP error response (JSON without SSE format)
        if first_line and not line.startswith("event:") and not line.startswith("data:"):
            first_line = False
            # Try to parse as JSON error
            try:
                error_data = json.loads(line)
                error_msg = None

                # Handle array of errors (FastAPI validation errors)
                if isinstance(error_data, list) and error_data:
                    error_msg = error_data[0].get("message", str(error_data))
                # Handle object with detail, error, or message
                elif isinstance(error_data, dict):
                    if "detail" in error_data or "error" in error_data or "message" in error_data:
                        error_msg = error_data.get("detail") or error_data.get("error") or error_data.get("message", "Error del servidor")
                        # Handle list inside detail
                        if isinstance(error_msg, list):
                            error_msg = error_msg[0].get("message", str(error_msg)) if error_msg else "Error del servidor"

                if error_msg:
                    result["error"] = str(error_msg)
                    spinner.stop(f"Error: {result['error']}", "error")
                    break
            except:
                pass
        first_line = False

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
                result["rag_enabled"] = parsed.get("rag_enabled", False)
                result["model"] = parsed.get("model", {})
                result["task_type"] = parsed.get("task_type", "")
                conv_id = parsed.get("conversation_id")
                rag_enabled = parsed.get("rag_enabled", False)
                model_info = parsed.get("model", {})
                model_name = model_info.get("model", "")
                rag_indicator = f" {GREEN}[RAG]{NC}" if rag_enabled else ""
                model_indicator = f" {DIM}({model_name}){NC}" if model_name else ""
                spinner.start(f"Conversacion #{conv_id}{rag_indicator}{model_indicator}")

            elif event_type == "thinking":
                model_info = parsed.get("model", {})
                model_name = model_info.get("model", "")
                if model_name:
                    spinner.update(f"Pensando... {DIM}({model_name}){NC}")
                else:
                    spinner.update("Pensando...")

            elif event_type == "text":
                content = parsed.get("content", "")
                msg_model = parsed.get("model", "")
                if content:
                    # First text chunk - stop spinner and show header with model
                    if not streaming_text:
                        spinner.stop()
                        model_tag = f" {DIM}({msg_model}){NC}" if msg_model else ""
                        sys.stderr.write(f"\n  {BOLD}{YELLOW}Agent:{NC}{model_tag}\n\n  ")
                        sys.stderr.flush()
                        streaming_text = True
                    # Convert markdown to ANSI and add indentation
                    formatted = markdown_to_ansi(content)
                    formatted = formatted.replace("\n", "\n  ")
                    sys.stderr.write(formatted)
                    sys.stderr.flush()
                    texts.append(content)

            elif event_type == "tool_requests":
                tool_calls = parsed.get("tool_calls", [])
                result["tool_requests"] = tool_calls
                result["conversation_id"] = parsed.get("conversation_id")
                tools_executed = len(tool_calls)

                # Capture session info from tool_requests
                result["session_cost"] = parsed.get("session_cost", 0)
                result["session_tokens"] = parsed.get("session_input_tokens", 0) + parsed.get("session_output_tokens", 0)

                # Just stop spinner - tool execution will show its own output
                spinner.stop()

            elif event_type == "complete":
                result["conversation_id"] = parsed.get("conversation_id")
                result["total_cost"] = parsed.get("total_cost", 0)
                result["total_tokens"] = parsed.get("total_input_tokens", 0) + parsed.get("total_output_tokens", 0)
                result["session_cost"] = parsed.get("session_cost", 0)
                result["session_tokens"] = parsed.get("session_input_tokens", 0) + parsed.get("session_output_tokens", 0)
                result["max_iterations_reached"] = parsed.get("max_iterations_reached", False)
                result["truncation_stats"] = parsed.get("truncation_stats", {})

                # Just stop spinner/add newline - summary shown by agent_chat.sh
                if streaming_text:
                    sys.stderr.write("\n")
                    sys.stderr.flush()
                else:
                    spinner.stop()

            elif event_type == "rate_limited":
                result["rate_limited"] = True
                result["rate_limit_message"] = parsed.get("message", "Rate limit alcanzado")
                result["conversation_id"] = parsed.get("conversation_id")
                spinner.stop(f"⚠️ {result['rate_limit_message']}", "info")

            elif event_type == "repaired":
                # Conversation was repaired due to interrupted session
                # Show as warning - conversation may continue processing
                result["repaired"] = True
                result["repaired_message"] = parsed.get("message", "Conversation repaired")
                # Show message but restart spinner (more events may come)
                spinner.stop(f"⚠️ Conversacion recuperada (estaba interrumpida)", "info")
                spinner.start("Continuando...")

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
result["text_streamed"] = streaming_text  # Flag to indicate text was already shown

# Combine all text responses
result["response"] = "".join(texts) if texts else ""

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
    local request_start_time="${2:-$(date +%s)}"  # Start time for total elapsed

    # Guardar tool_requests en archivo temporal
    local tmp_requests=$(mktemp)
    echo "$tool_requests" > "$tmp_requests"

    python3 - "$tmp_requests" "$AGENT_SCRIPT_DIR" "$request_start_time" << 'PYEOF'
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
request_start_time = int(sys.argv[3]) if len(sys.argv) > 3 else int(time.time())

with open(tmp_file) as f:
    tool_requests = json.load(f)

results = []
total_tools = len(tool_requests)

# Calculate total elapsed time
total_elapsed = int(time.time()) - request_start_time

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

    # Start spinner with tool info
    spinner = ToolSpinner()
    spinner.start(f"{icon} {tc_name} {DIM}{detail}{NC}")

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
    preview = output[:50].replace("\n", " ").strip()
    if len(output) > 50:
        preview += "..."

    # Print compact result: icon tool detail → result
    if success:
        sys.stderr.write(f"  {GREEN}✓{NC} {icon} {tc_name} {DIM}{detail}{NC} → {DIM}{preview}{NC}\n")
    else:
        sys.stderr.write(f"  {RED}✗{NC} {icon} {tc_name} {DIM}{detail}{NC} → {preview}\n")
    sys.stderr.flush()

    results.append({
        "tool_call_id": tc_id,
        "tool_name": tc_name,
        "result": output
    })

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
    local subagent_id="${4:-}"    # Optional: ID del subagente a usar

    local current_conv_id="$conversation_id"
    local tool_results=""
    local iteration=0
    local max_tool_iterations=30  # Limite de seguridad (se pregunta antes de salir)
    local start_time=$(date +%s)  # Track total elapsed time

    # Accumulate session costs across all HTTP calls
    local accumulated_session_tokens=0
    local accumulated_session_cost=0

    # Detect and encode images from the prompt
    local images_json=""
    local cleaned_prompt="$prompt"
    if [ -n "$prompt" ]; then
        images_json=$(detect_and_encode_images "$prompt")
        if [ -n "$images_json" ] && [ "$images_json" != "[]" ]; then
            # Remove image paths from prompt text
            cleaned_prompt=$(remove_image_paths_from_text "$prompt")
            local num_images=$(echo "$images_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
            if [ "$num_images" -gt 0 ]; then
                echo -e "  ${GREEN}📎${NC} ${num_images} imagen(es) detectada(s)" >&2
            fi
        fi
    fi

    while [ $iteration -lt $max_tool_iterations ]; do
        iteration=$((iteration + 1))

        # Llamar al servidor
        local response
        if [ $iteration -eq 1 ]; then
            # Primera llamada: enviar prompt (con subagent_id e imagenes si existen)
            response=$(send_chat_hybrid "$cleaned_prompt" "$current_conv_id" "" "$max_iterations" "$subagent_id" "$images_json")
        else
            # Llamadas siguientes: enviar tool_results (sin imagenes, mantener subagent_id)
            response=$(send_chat_hybrid "" "$current_conv_id" "$tool_results" "$max_iterations" "$subagent_id" "")
        fi

        # Verificar error
        local error=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error') or '')" 2>/dev/null)
        if [ -n "$error" ]; then
            # Check if it's an auth error (case insensitive patterns)
            local error_lower=$(echo "$error" | tr '[:upper:]' '[:lower:]')
            if [[ "$error_lower" == *"not authenticated"* ]] || [[ "$error_lower" == *"token"* ]] || \
               [[ "$error_lower" == *"expired"* ]] || [[ "$error_lower" == *"401"* ]] || \
               [[ "$error_lower" == *"authentication"* ]] || [[ "$error_lower" == *"unauthorized"* ]] || \
               [[ "$error_lower" == *"not authorized"* ]] || [[ "$error_lower" == *"access denied"* ]]; then
                echo '{"error": "auth_expired", "message": "Tu sesion ha expirado"}'
                return 2  # Special return code for auth errors
            fi
            echo "$response"
            return 1
        fi

        # Obtener conversation_id
        current_conv_id=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('conversation_id') or '')" 2>/dev/null)

        # Accumulate session costs from this response
        local this_session_tokens=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_tokens', 0))" 2>/dev/null)
        local this_session_cost=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_cost', 0))" 2>/dev/null)
        accumulated_session_tokens=$(python3 -c "print(int($accumulated_session_tokens) + int($this_session_tokens))" 2>/dev/null || echo "$accumulated_session_tokens")
        accumulated_session_cost=$(python3 -c "print($accumulated_session_cost + $this_session_cost)" 2>/dev/null || echo "$accumulated_session_cost")

        # Verificar si hay tool_requests
        local tool_requests=$(echo "$response" | python3 -c "import sys,json; r=json.load(sys.stdin).get('tool_requests'); print(json.dumps(r) if r else '')" 2>/dev/null)

        if [ -n "$tool_requests" ] && [ "$tool_requests" != "null" ]; then
            # Ejecutar tools localmente (pass start_time for elapsed calculation)
            tool_results=$(execute_tools_locally "$tool_requests" "$start_time")

            # Validate tool_results is valid JSON
            if [ -z "$tool_results" ]; then
                echo '{"error": "Tool execution returned empty results", "response": ""}'
                return 1
            fi

            # Verify it's valid JSON array
            local is_valid=$(echo "$tool_results" | python3 -c "import sys,json; r=json.load(sys.stdin); print('yes' if isinstance(r, list) and len(r) > 0 else 'no')" 2>/dev/null)
            if [ "$is_valid" != "yes" ]; then
                echo "{\"error\": \"Invalid tool results format\", \"response\": \"\", \"debug\": $(echo "$tool_results" | head -c 200 | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')}"
                return 1
            fi

            # Continuar el loop para enviar resultados
            continue
        fi

        # No hay tool_requests, devolver respuesta final
        # Add total elapsed time and accumulated session costs to response
        local total_elapsed=$(($(date +%s) - start_time))
        echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
data['total_elapsed'] = $total_elapsed
data['session_tokens'] = $accumulated_session_tokens
data['session_cost'] = $accumulated_session_cost
print(json.dumps(data))
"
        return 0
    done

    # Max tool iterations reached - return special response for CLI to handle
    local total_elapsed=$(($(date +%s) - start_time))
    echo "{\"error\": null, \"max_tool_iterations_reached\": true, \"conversation_id\": \"$current_conv_id\", \"total_elapsed\": $total_elapsed, \"session_tokens\": $accumulated_session_tokens, \"session_cost\": $accumulated_session_cost, \"response\": \"\"}"
    return 0
}
