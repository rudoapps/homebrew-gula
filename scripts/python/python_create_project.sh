#!/usr/bin/env bash

# Constantes
execPath=$PWD


get_token() {
    echo ""
    echo "┌──────────────────────────────────────────────"  
    echo "│"
    echo "│ Validando key"
    echo "│ "
    
    # Validar que KEY no esté vacío
    if [ -z "$KEY" ]; then
        echo "│"
        echo "│ ❌ Error: Se requiere una KEY para crear proyectos."
        echo "│ ✅ Uso: gula create python --key=tu_clave_aqui"
        echo "│"
        echo "└──────────────────────────────────────────────"
        exit 1
    fi

    GULA_COMMAND="create"
    get_access_token $KEY "back"
}

# Función de ayuda
helpFun(){
    echo -e "\n\033[1;1m[Uso]\n$0\033[0m"
    echo -e "\n\033[1;1mEste script configurará un nuevo proyecto Python basado en el arquetipo.\033[0m"
    exit 1
}

checkResult(){
    if [ $? != 0 ]
    then
        echo "│"
        echo "│ ❌ Error: Paso '$1' FALLÓ."
        echo "│"
    exit 1
    fi
}

validate_project_name() {
    if [[ -z "$projectPath" || "$projectPath" =~ ^[[:space:]]*$ ]]; then
        echo "│"
        echo "│ ❌ Error: El nombre del proyecto no puede estar vacío ni ser solo espacios."
        echo "│"
        exit 1
    fi

    # Validar caracteres válidos (letras, números, guiones y guiones bajos)
    if [[ ! "$projectPath" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "│"
        echo "│ ❌ Error: El nombre del proyecto contiene caracteres no válidos."
        echo "│ ✅ Usa solo letras, números, guiones (-), guiones bajos (_) y puntos (.)"
        echo "│"
        exit 1
    fi
}


python_create_project() {
    read -p "Introduce la ruta de destino para el nuevo proyecto (por ejemplo, ../NuevaApp): " projectPath
    validate_project_name
    echo ""
    set -eu
    while :; do
      echo "Elige stack (1-2):"
      echo "1) fastapi"
      echo "2) django"
      printf "> "
      read ans || exit 1

      case "$ans" in
        1|fastapi) STACK="fastapi"; break ;;
        2|django) STACK="django"; break ;;
        *) echo "Opción inválida. Usa 1/2 o fastapi/django." ;;
      esac
    done
    echo "Stack seleccionado: $STACK"

    # Si no se proporciona BRANCH globalmente, usar el branch por defecto según el stack
    if [ -z "${BRANCH:-}" ]; then
        case "$STACK" in
          fastapi)
            BRANCH="fastapi"
            ;;
          django)
            BRANCH="main"
            ;;
        esac
    fi

    if [ -z "$projectPath" ]; then
        echo "│"
        echo "│ ❌  Error: Faltan parámetros obligatorios."
        echo "│"
        helpFun
        exit 1
    fi

    if [ -d "$projectPath" ]; then
        echo "│"
        echo "│ ❌  La carpeta '$projectPath' ya existe. Por seguridad no se sobrescribirá."
        echo "│"   
        exit 1
    fi

    # Carpeta temporal
    TEMP_CLONE_DIR="temp-archetype"
    if [ -d "$TEMP_CLONE_DIR" ]; then
        echo "│"
        echo "│ 🗑️  Eliminando carpeta temporal existente: $TEMP_CLONE_DIR"
        echo "│"
        rm -rf "$TEMP_CLONE_DIR"
    fi
    
    get_token

    echo "│"
    echo "│ ✅ Clonando arquetipo en carpeta temporal..."
    echo "│ 🌿 Usando rama: $BRANCH"

    git clone --branch "$BRANCH" --depth 1  "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/architecture-python.git" "$TEMP_CLONE_DIR"
    checkResult "Clonando repositorio arquetipo"

    echo "│"
    echo "│ ✅ Eliminando .git para limpiar el historial..."
    rm -rf "$TEMP_CLONE_DIR/.git"

    echo "│"
    echo "│ ✅ Copiando contenido en: '$projectPath'..."


    mkdir -p "$projectPath"
    cp -R "$TEMP_CLONE_DIR"/. "$projectPath"
    checkResult "Copiando contenido del arquetipo"

    echo "│"
    echo "│ ✅ Configurando entorno Python con uv..."
    echo "│"

    # Cambiar al directorio del proyecto
    cd "$projectPath"

    # Verificar si uv está instalado
    if ! command -v uv &> /dev/null; then
        echo "│ 📦 uv no está instalado. Instalando..."
        echo "│"
        
        # Detectar el sistema operativo e instalar uv
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            if command -v brew &> /dev/null; then
                brew install uv
            else
                curl -LsSf https://astral.sh/uv/install.sh | sh
                source ~/.bashrc 2>/dev/null || source ~/.zshrc 2>/dev/null || true
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            # Linux
            curl -LsSf https://astral.sh/uv/install.sh | sh
            source ~/.bashrc 2>/dev/null || source ~/.zshrc 2>/dev/null || true
        else
            echo "│ ⚠️  Sistema operativo no soportado para instalación automática de uv"
            echo "│    Instala uv manualmente desde: https://github.com/astral-sh/uv"
            echo "│"
        fi
        
        # Verificar si la instalación fue exitosa
        if ! command -v uv &> /dev/null; then
            echo "│ ❌ Error: No se pudo instalar uv automáticamente"
            echo "│    Instala uv manualmente y ejecuta nuevamente"
            echo "│"
            cd "$execPath"
            rm -rf "$TEMP_CLONE_DIR"
            exit 1
        else
            echo "│ ✅ uv instalado correctamente"
            echo "│"
        fi
    else
        echo "│ ✅ uv ya está instalado"
        echo "│"
    fi

    # Crear entorno virtual con uv
    echo "│ 🐍 Creando entorno virtual..."
    uv venv
    checkResult "Creación del entorno virtual con uv"

    # Activar entorno virtual y sincronizar dependencias
    echo "│"
    echo "│ 📦 Instalando dependencias..."
    
    # En lugar de source (que puede no funcionar en todos los shells), usar uv run
    uv sync
    checkResult "Sincronización de dependencias con uv"

    echo "│"
    echo "│ ✅ Entorno Python configurado correctamente"
    echo "│ 💡 Para activar el entorno: source .venv/bin/activate"
    echo "│ 💡 O usar directamente: uv run python tu_script.py"
    echo "│"

    # Volver al directorio original
    cd "$execPath"

    echo "│"
    echo "│ ✅ Eliminando carpeta temporal..."

    rm -rf "$TEMP_CLONE_DIR"

    echo "│"
    echo "│ 👍 Proyecto python preparado en: $(pwd)"

    # Registrar la creación del proyecto
    log_project_creation "python" "$projectPath" "$(pwd)" "${BRANCH:-main}" "success" "Python project created with stack: ${STACK:-fastapi}"

    echo "│"
    echo "└──────────────────────────────────────────────"

}

