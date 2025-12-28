#!/bin/bash

# Agent CLI module for Gula
# Provides interaction with the Agentic AI server
#
# This is the main entry point that sources all agent modules:
#   - agent_config.sh     : Configuration and dependency management
#   - agent_ui.sh         : UI utilities (colors, spinners)
#   - agent_local_tools.sh: Local tool execution
#   - agent_auth.sh       : Authentication (login, logout, token refresh)
#   - agent_api.sh        : API communication (SSE, hybrid chat)
#   - agent_chat.sh       : Chat UI (single message, interactive mode)

# ============================================================================
# MODULE LOADING
# ============================================================================

# Get script directory
AGENT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load all modules in dependency order
source "$AGENT_SCRIPT_DIR/agent_config.sh"      # Configuration (must be first)
source "$AGENT_SCRIPT_DIR/agent_ui.sh"          # UI utilities
source "$AGENT_SCRIPT_DIR/agent_local_tools.sh" # Local tool execution
source "$AGENT_SCRIPT_DIR/agent_auth.sh"        # Authentication
source "$AGENT_SCRIPT_DIR/agent_api.sh"         # API communication
source "$AGENT_SCRIPT_DIR/agent_chat.sh"        # Chat UI

# ============================================================================
# HELP
# ============================================================================

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

# ============================================================================
# COMMAND DISPATCHER
# ============================================================================

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
