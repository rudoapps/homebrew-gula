#!/bin/bash

# Agent Configuration Module
# Handles configuration storage and retrieval

# ============================================================================
# CONFIGURATION
# ============================================================================

AGENT_CONFIG_DIR="$HOME/.config/gula-agent"
AGENT_CONFIG_FILE="$AGENT_CONFIG_DIR/config.json"
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
