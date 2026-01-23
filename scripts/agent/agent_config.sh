#!/bin/bash

# Agent Configuration Module
# Handles configuration storage and retrieval

# ============================================================================
# CONFIGURATION
# ============================================================================

AGENT_CONFIG_DIR="$HOME/.config/gula-agent"
AGENT_CONFIG_FILE="$AGENT_CONFIG_DIR/config.json"
AGENT_CONVERSATIONS_FILE="$AGENT_CONFIG_DIR/conversations.json"
AGENT_SETUP_DONE_FILE="$AGENT_CONFIG_DIR/.setup_done"
AGENT_UNDO_DIR="$AGENT_CONFIG_DIR/undo"
AGENT_API_URL="${AGENT_API_URL:-https://agent.rudo.es/api/v1}"

# ============================================================================
# PERFORMANCE CACHING
# ============================================================================

# Project ID cache (per directory)
PROJECT_ID_CACHE=""
PROJECT_DIR_CACHE=""

# Config JSON cache (using temp file for bash 3.2 compatibility)
CONFIG_CACHE_FILE=""
CONFIG_CACHE_MTIME=""
CONFIG_CACHE_TEMP=""

# Required and optional dependencies
AGENT_REQUIRED_DEPS=("python3" "curl")
AGENT_OPTIONAL_DEPS=("glow")

# Detect jq for faster JSON parsing
HAS_JQ=$(command -v jq &>/dev/null && echo "1" || echo "")

# ============================================================================
# JSON HELPER FUNCTIONS (jq with python fallback)
# ============================================================================

# Get a value from JSON string
# Usage: json_get "$json" "field"
# Usage: json_get "$json" "field" "default"
json_get() {
    local json="$1"
    local field="$2"
    local default="${3:-}"

    if [ -n "$HAS_JQ" ]; then
        local result=$(echo "$json" | jq -r ".$field // empty" 2>/dev/null)
        [ -n "$result" ] && echo "$result" || echo "$default"
    else
        local result=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); v=d.get('$field'); print('' if v is None else v)" 2>/dev/null)
        [ -n "$result" ] && echo "$result" || echo "$default"
    fi
}

# Get nested value from JSON string
# Usage: json_get_nested "$json" ".field.subfield"
json_get_nested() {
    local json="$1"
    local path="$2"
    local default="${3:-}"

    if [ -n "$HAS_JQ" ]; then
        local result=$(echo "$json" | jq -r "$path // empty" 2>/dev/null)
        [ -n "$result" ] && echo "$result" || echo "$default"
    else
        # For Python, convert jq path to Python: .field.sub -> ['field']['sub']
        local py_path=$(echo "$path" | sed "s/\./']['/g" | sed "s/^']//" | sed "s/$/']/" | sed "s/^\['/['/")
        local result=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d$py_path)" 2>/dev/null)
        [ -n "$result" ] && echo "$result" || echo "$default"
    fi
}

# Check if JSON has error field
# Usage: json_get_error "$json" -> returns error message or empty
json_get_error() {
    local json="$1"

    if [ -n "$HAS_JQ" ]; then
        echo "$json" | jq -r '.error // .detail // empty' 2>/dev/null
    else
        echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error') or d.get('detail') or '')" 2>/dev/null
    fi
}

# Check if JSON field equals a value
# Usage: json_check "$json" "field" "value" && echo "match"
json_check() {
    local json="$1"
    local field="$2"
    local expected="$3"

    if [ -n "$HAS_JQ" ]; then
        local result=$(echo "$json" | jq -r ".$field" 2>/dev/null)
        [ "$result" = "$expected" ]
    else
        local result=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$field'))" 2>/dev/null)
        [ "$result" = "$expected" ]
    fi
}

# Check if JSON field is truthy
# Usage: json_is_true "$json" "field" && echo "true"
json_is_true() {
    local json="$1"
    local field="$2"

    if [ -n "$HAS_JQ" ]; then
        local result=$(echo "$json" | jq -r ".$field" 2>/dev/null)
        [ "$result" = "true" ] || [ "$result" = "True" ]
    else
        local result=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$field', False))" 2>/dev/null)
        [ "$result" = "True" ] || [ "$result" = "true" ]
    fi
}

# Get numeric value from JSON (with default 0)
# Usage: json_get_num "$json" "field"
json_get_num() {
    local json="$1"
    local field="$2"
    local default="${3:-0}"

    if [ -n "$HAS_JQ" ]; then
        local result=$(echo "$json" | jq -r ".$field // $default" 2>/dev/null)
        echo "${result:-$default}"
    else
        local result=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$field', $default))" 2>/dev/null)
        echo "${result:-$default}"
    fi
}

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

# Initialize config directory and file
init_agent_config() {
    mkdir -p "$AGENT_CONFIG_DIR"
    if [ ! -f "$AGENT_CONFIG_FILE" ]; then
        echo '{"api_url":"'"$AGENT_API_URL"'","access_token":null,"refresh_token":null}' > "$AGENT_CONFIG_FILE"
    fi

    # Cleanup old backups in background (non-blocking)
    # Run once per session to avoid overhead
    if [ -z "${AGENT_CLEANUP_DONE:-}" ]; then
        cleanup_old_backups 20 2>/dev/null &
        export AGENT_CLEANUP_DONE=1
    fi
}

# Get value from config - WITH CACHE
get_agent_config() {
    local key=$1

    if [ ! -f "$AGENT_CONFIG_FILE" ]; then
        return 0
    fi

    # Check if cache is valid
    local current_mtime=$(stat -f %m "$AGENT_CONFIG_FILE" 2>/dev/null || stat -c %Y "$AGENT_CONFIG_FILE" 2>/dev/null)

    # Invalidate cache if file changed or different file
    if [[ "$CONFIG_CACHE_FILE" != "$AGENT_CONFIG_FILE" ]] || [[ "$CONFIG_CACHE_MTIME" != "$current_mtime" ]]; then
        # Reload cache - parse all keys at once into temp file (bash 3.2 compatible)
        # Clean up old temp file
        [ -n "$CONFIG_CACHE_TEMP" ] && [ -f "$CONFIG_CACHE_TEMP" ] && rm -f "$CONFIG_CACHE_TEMP"

        CONFIG_CACHE_TEMP=$(mktemp)

        if [ -n "$HAS_JQ" ]; then
            jq -r 'to_entries | .[] | "\(.key)=\(.value // "")"' "$AGENT_CONFIG_FILE" 2>/dev/null > "$CONFIG_CACHE_TEMP"
        else
            python3 -c "import json; d=json.load(open('$AGENT_CONFIG_FILE')); [print(f'{k}={v}' if v is not None else f'{k}=') for k,v in d.items()]" 2>/dev/null > "$CONFIG_CACHE_TEMP"
        fi

        CONFIG_CACHE_FILE="$AGENT_CONFIG_FILE"
        CONFIG_CACHE_MTIME="$current_mtime"
    fi

    # Return cached value from temp file
    if [ -f "$CONFIG_CACHE_TEMP" ]; then
        grep "^${key}=" "$CONFIG_CACHE_TEMP" 2>/dev/null | cut -d'=' -f2-
    fi
}

# Set value in config
set_agent_config() {
    local key=$1
    local value=$2
    if [ -f "$AGENT_CONFIG_FILE" ]; then
        if [ -n "$HAS_JQ" ]; then
            local tmp=$(mktemp)
            if [ "$value" = "null" ]; then
                jq ".$key = null" "$AGENT_CONFIG_FILE" > "$tmp" && mv "$tmp" "$AGENT_CONFIG_FILE"
            else
                jq ".$key = \"$value\"" "$AGENT_CONFIG_FILE" > "$tmp" && mv "$tmp" "$AGENT_CONFIG_FILE"
            fi
        else
            python3 -c "
import json
config = json.load(open('$AGENT_CONFIG_FILE'))
config['$key'] = '$value' if '$value' != 'null' else None
json.dump(config, open('$AGENT_CONFIG_FILE', 'w'), indent=2)
"
        fi

        # Invalidate cache after modification
        CONFIG_CACHE_MTIME=""

        # Clean up temp file
        if [ -n "$CONFIG_CACHE_TEMP" ] && [ -f "$CONFIG_CACHE_TEMP" ]; then
            rm -f "$CONFIG_CACHE_TEMP"
            CONFIG_CACHE_TEMP=""
        fi
    fi
}

# ============================================================================
# PER-PROJECT CONVERSATION TRACKING
# ============================================================================

# Get project identifier (git remote URL or path) - WITH CACHE
get_project_id() {
    local current_dir="$(pwd)"

    # Return cached value if directory hasn't changed
    if [[ "$PROJECT_DIR_CACHE" == "$current_dir" ]] && [[ -n "$PROJECT_ID_CACHE" ]]; then
        echo "$PROJECT_ID_CACHE"
        return 0
    fi

    # Calculate project ID
    local git_url=$(git remote get-url origin 2>/dev/null)
    if [ -n "$git_url" ]; then
        # Normalize: remove .git suffix and user@ prefix
        PROJECT_ID_CACHE=$(echo "$git_url" | sed 's/\.git$//' | sed 's|.*@||' | sed 's|:|/|')
    else
        # Fallback to current directory
        PROJECT_ID_CACHE="$current_dir"
    fi

    # Cache for this directory
    PROJECT_DIR_CACHE="$current_dir"

    echo "$PROJECT_ID_CACHE"
}

# Save last conversation ID for current project
save_project_conversation() {
    local conversation_id="$1"
    local project_id=$(get_project_id)

    # Skip if conversation_id is empty or None
    if [ -z "$conversation_id" ] || [ "$conversation_id" = "None" ] || [ "$conversation_id" = "null" ]; then
        return
    fi

    # Initialize file if needed
    if [ ! -f "$AGENT_CONVERSATIONS_FILE" ]; then
        echo '{}' > "$AGENT_CONVERSATIONS_FILE"
    fi

    python3 -c "
import json
import time

conv_id = '$conversation_id'
if not conv_id or conv_id in ('None', 'null', ''):
    exit(0)

try:
    with open('$AGENT_CONVERSATIONS_FILE') as f:
        data = json.load(f)
except:
    data = {}

data['$project_id'] = {
    'conversation_id': int(conv_id),
    'updated_at': time.time()
}

with open('$AGENT_CONVERSATIONS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
}

# Get last conversation ID for current project
get_project_conversation() {
    local project_id=$(get_project_id)

    if [ ! -f "$AGENT_CONVERSATIONS_FILE" ]; then
        echo ""
        return
    fi

    python3 -c "
import json
import time

try:
    with open('$AGENT_CONVERSATIONS_FILE') as f:
        data = json.load(f)

    entry = data.get('$project_id', {})
    conv_id = entry.get('conversation_id')
    updated_at = entry.get('updated_at', 0)

    # Only return if less than 24 hours old
    if conv_id and (time.time() - updated_at) < 86400:
        print(conv_id)
    else:
        print('')
except:
    print('')
"
}

# Clear conversation for current project
clear_project_conversation() {
    local project_id=$(get_project_id)

    if [ ! -f "$AGENT_CONVERSATIONS_FILE" ]; then
        return
    fi

    python3 -c "
import json

try:
    with open('$AGENT_CONVERSATIONS_FILE') as f:
        data = json.load(f)

    if '$project_id' in data:
        del data['$project_id']

    with open('$AGENT_CONVERSATIONS_FILE', 'w') as f:
        json.dump(data, f, indent=2)
except:
    pass
"
}

# ============================================================================
# DEPENDENCY MANAGEMENT
# ============================================================================

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

# ============================================================================
# IMAGE HANDLING
# ============================================================================

# Detect image file paths in text and encode them
# Returns JSON array of {data: base64, media_type: "image/..."}
detect_and_encode_images() {
    local text="$1"

    python3 - "$text" << 'PYEOF'
import sys
import os
import re
import base64
import json

text = sys.argv[1]
images = []

# Patterns for image file paths
# Matches: /path/to/file.png, ~/Desktop/image.jpg, ./screenshot.png
image_extensions = r'\.(png|jpg|jpeg|gif|webp|bmp|tiff?)$'
path_patterns = [
    r'(?:^|\s)(~?(?:/[^\s]+)+' + image_extensions + r')',  # Absolute/home paths
    r'(?:^|\s)(\.\.?/[^\s]+' + image_extensions + r')',     # Relative paths
]

for pattern in path_patterns:
    matches = re.findall(pattern, text, re.IGNORECASE)
    for match in matches:
        # Handle tuple from groups
        path = match[0] if isinstance(match, tuple) else match
        path = path.strip()

        # Expand ~
        expanded_path = os.path.expanduser(path)

        if os.path.isfile(expanded_path):
            try:
                with open(expanded_path, 'rb') as f:
                    data = base64.b64encode(f.read()).decode('utf-8')

                # Determine media type
                ext = os.path.splitext(expanded_path)[1].lower()
                media_types = {
                    '.png': 'image/png',
                    '.jpg': 'image/jpeg',
                    '.jpeg': 'image/jpeg',
                    '.gif': 'image/gif',
                    '.webp': 'image/webp',
                    '.bmp': 'image/bmp',
                    '.tiff': 'image/tiff',
                    '.tif': 'image/tiff',
                }
                media_type = media_types.get(ext, 'image/png')

                images.append({
                    'data': data,
                    'media_type': media_type,
                    'source_path': path  # For reference
                })
            except Exception as e:
                print(f"Warning: Could not read image {path}: {e}", file=sys.stderr)

print(json.dumps(images))
PYEOF
}

# Remove image paths from text (after encoding)
remove_image_paths_from_text() {
    local text="$1"

    python3 - "$text" << 'PYEOF'
import sys
import re

text = sys.argv[1]

# Same patterns as detection
image_extensions = r'\.(png|jpg|jpeg|gif|webp|bmp|tiff?)(\s|$)'
path_patterns = [
    r'~?(?:/[^\s]+)+' + image_extensions,
    r'\.\.?/[^\s]+' + image_extensions,
]

for pattern in path_patterns:
    text = re.sub(pattern, ' ', text, flags=re.IGNORECASE)

# Clean up extra whitespace
text = ' '.join(text.split())
print(text)
PYEOF
}

# Check if clipboard has an image (macOS only)
has_clipboard_image() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Check if clipboard contains image data
        osascript -e 'clipboard info' 2>/dev/null | grep -q 'TIFF\|PNG\|JPEG\|GIF' && return 0
    fi
    return 1
}

# Get clipboard image as base64 (macOS only)
get_clipboard_image_base64() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo ""
        return 1
    fi

    python3 << 'PYEOF'
import subprocess
import base64
import sys

try:
    # Get clipboard as PNG using osascript + pngpaste or similar
    # First try using pngpaste if available
    try:
        result = subprocess.run(['pngpaste', '-'], capture_output=True, timeout=5)
        if result.returncode == 0 and result.stdout:
            print(base64.b64encode(result.stdout).decode('utf-8'))
            sys.exit(0)
    except FileNotFoundError:
        pass

    # Fallback: use osascript to get TIFF and convert
    script = '''
    set imgData to the clipboard as «class PNGf»
    return imgData
    '''
    result = subprocess.run(['osascript', '-e', script], capture_output=True, timeout=5)
    if result.returncode == 0 and result.stdout:
        # Remove the "«data PNGf...»" wrapper if present
        data = result.stdout
        print(base64.b64encode(data).decode('utf-8'))
        sys.exit(0)

    print("")
except Exception as e:
    print("", file=sys.stderr)
    sys.exit(1)
PYEOF
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

# ============================================================================
# UNDO / BACKUP SYSTEM
# ============================================================================

# Create a backup of a file before modification
# Usage: create_file_backup "/path/to/file.py"
# Returns: backup path
create_file_backup() {
    local file_path="$1"

    # Only backup if file exists
    if [ ! -f "$file_path" ]; then
        return 0
    fi

    # Create undo directory
    mkdir -p "$AGENT_UNDO_DIR"

    # Generate backup filename with timestamp
    local timestamp=$(date +%s)
    local filename=$(basename "$file_path")
    local backup_path="$AGENT_UNDO_DIR/${filename}.${timestamp}.bak"

    # Copy file to backup location
    cp "$file_path" "$backup_path"

    # Store metadata
    local metadata_path="$AGENT_UNDO_DIR/${filename}.${timestamp}.meta"
    cat > "$metadata_path" <<EOF
{
    "original_path": "$file_path",
    "backup_path": "$backup_path",
    "timestamp": $timestamp,
    "date": "$(date -r $timestamp '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d @$timestamp '+%Y-%m-%d %H:%M:%S' 2>/dev/null)",
    "size": $(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)
}
EOF

    echo "$backup_path"
}

# List available backups
# Usage: list_file_backups
list_file_backups() {
    if [ ! -d "$AGENT_UNDO_DIR" ]; then
        echo "No hay backups disponibles"
        return 0
    fi

    local backups=$(ls -t "$AGENT_UNDO_DIR"/*.bak 2>/dev/null)

    if [ -z "$backups" ]; then
        echo "No hay backups disponibles"
        return 0
    fi

    echo ""
    echo -e "${BOLD}Backups disponibles:${NC}"
    echo ""

    local count=0
    for backup in $backups; do
        count=$((count + 1))
        local meta="${backup%.bak}.meta"

        if [ -f "$meta" ]; then
            local original=$(json_get "$(cat "$meta")" "original_path")
            local date=$(json_get "$(cat "$meta")" "date")
            local size=$(json_get "$(cat "$meta")" "size")

            echo -e "  ${BOLD}$count)${NC} ${CYAN}$(basename "$original")${NC}"
            echo -e "      ${DIM}$date · $size bytes${NC}"
            echo -e "      ${DIM}$original${NC}"
            echo ""
        else
            echo -e "  ${BOLD}$count)${NC} $(basename "$backup")"
            echo ""
        fi

        # Limit to 10 most recent
        if [ $count -ge 10 ]; then
            break
        fi
    done
}

# Restore a file from backup
# Usage: restore_from_backup [backup_number]
restore_from_backup() {
    local backup_number="${1:-1}"

    if [ ! -d "$AGENT_UNDO_DIR" ]; then
        echo -e "${RED}No hay backups disponibles${NC}"
        return 1
    fi

    local backups=($(ls -t "$AGENT_UNDO_DIR"/*.bak 2>/dev/null))

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}No hay backups disponibles${NC}"
        return 1
    fi

    # Get the specified backup (1-indexed)
    local index=$((backup_number - 1))

    if [ $index -lt 0 ] || [ $index -ge ${#backups[@]} ]; then
        echo -e "${RED}Número de backup inválido${NC}"
        return 1
    fi

    local backup_path="${backups[$index]}"
    local meta_path="${backup_path%.bak}.meta"

    if [ ! -f "$meta_path" ]; then
        echo -e "${RED}No se encontró metadata del backup${NC}"
        return 1
    fi

    local original_path=$(json_get "$(cat "$meta_path")" "original_path")
    local date=$(json_get "$(cat "$meta_path")" "date")

    echo ""
    echo -e "${BOLD}Restaurar backup:${NC}"
    echo -e "  Archivo: ${CYAN}$(basename "$original_path")${NC}"
    echo -e "  Fecha: ${DIM}$date${NC}"
    echo -e "  Destino: ${DIM}$original_path${NC}"
    echo ""

    # Ask for confirmation (skip in non-interactive mode)
    if [ -t 0 ]; then
        read -p "¿Confirmar restauración? (s/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            echo "Cancelado"
            return 0
        fi
    fi

    # Create backup of current file before restoring
    if [ -f "$original_path" ]; then
        create_file_backup "$original_path" > /dev/null
        echo -e "${DIM}Backup del archivo actual creado${NC}"
    fi

    # Restore from backup
    cp "$backup_path" "$original_path"

    echo -e "${GREEN}✓${NC} Archivo restaurado exitosamente"
    echo ""
}

# Clean old backups (keep last N backups per file)
# Usage: cleanup_old_backups [keep_count]
cleanup_old_backups() {
    local keep_count="${1:-20}"

    if [ ! -d "$AGENT_UNDO_DIR" ]; then
        return 0
    fi

    # Group backups by original filename
    local files_seen=()
    local backups_to_delete=()

    for backup in $(ls -t "$AGENT_UNDO_DIR"/*.bak 2>/dev/null); do
        local base=$(basename "$backup" | sed 's/\.[0-9]*\.bak$//')

        # Count how many backups we've seen for this file
        local count=0
        for seen in "${files_seen[@]}"; do
            if [ "$seen" = "$base" ]; then
                count=$((count + 1))
            fi
        done

        files_seen+=("$base")

        # If we've seen more than keep_count for this file, mark for deletion
        if [ $count -ge $keep_count ]; then
            backups_to_delete+=("$backup")
            local meta="${backup%.bak}.meta"
            [ -f "$meta" ] && backups_to_delete+=("$meta")
        fi
    done

    # Delete old backups
    if [ ${#backups[@]} -gt 0 ]; then
        for file in "${backups_to_delete[@]}"; do
            rm -f "$file"
        done
        echo -e "${DIM}Limpiados ${#backups_to_delete[@]} backups antiguos${NC}"
    fi
}
