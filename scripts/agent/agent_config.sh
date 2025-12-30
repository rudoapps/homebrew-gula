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
AGENT_API_URL="${AGENT_API_URL:-http://localhost:8002/api/v1}"

# Required and optional dependencies
AGENT_REQUIRED_DEPS=("python3" "curl")
AGENT_OPTIONAL_DEPS=("glow")

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

# Initialize config directory and file
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

# ============================================================================
# PER-PROJECT CONVERSATION TRACKING
# ============================================================================

# Get project identifier (git remote URL or path)
get_project_id() {
    local git_url=$(git remote get-url origin 2>/dev/null)
    if [ -n "$git_url" ]; then
        # Normalize: remove .git suffix and user@ prefix
        echo "$git_url" | sed 's/\.git$//' | sed 's|.*@||' | sed 's|:|/|'
    else
        # Fallback to current directory
        pwd
    fi
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
