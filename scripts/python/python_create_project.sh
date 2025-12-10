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

    # Stack fijo: fastapi
    STACK="fastapi"
    echo "Stack: $STACK"

    # Rama fija: develop
    if [ -z "${BRANCH:-}" ]; then
        BRANCH="develop"
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
    echo "│"
    echo "│ 📝 Creando archivo de auditoría .gula.log..."

    # Ya estamos en el directorio del proyecto
    TIMESTAMP_LOG=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    BRANCH_LOG="${BRANCH:-main}"
    COMMIT_LOG=""
    CREATED_BY_LOG="unknown"

    # Intentar obtener el username
    if [ -n "$KEY" ]; then
        if command -v get_username_from_api >/dev/null 2>&1; then
            CREATED_BY_LOG=$(get_username_from_api "$KEY" 2>/dev/null | tr -d '\n\r' || echo "unknown")
            # Si está vacío, usar "unknown"
            [ -z "$CREATED_BY_LOG" ] && CREATED_BY_LOG="unknown"
        fi
    fi

    # Crear el archivo .gula.log
    echo "{
  \"project_info\": {
    \"created\": \"$TIMESTAMP_LOG\",
    \"platform\": \"python\",
    \"project_name\": \"$projectPath\",
    \"branch\": \"$BRANCH_LOG\",
    \"commit\": \"$COMMIT_LOG\",
    \"created_by\": \"$CREATED_BY_LOG\",
    \"stack\": \"${STACK:-fastapi}\",
    \"gula_version\": \"$VERSION\"
  },
  \"operations\": [
    {
      \"timestamp\": \"$TIMESTAMP_LOG\",
      \"operation\": \"create\",
      \"platform\": \"python\",
      \"module\": \"$projectPath\",
      \"branch\": \"$BRANCH_LOG\",
      \"commit\": \"$COMMIT_LOG\",
      \"status\": \"success\",
      \"details\": \"Python project created with stack: ${STACK:-fastapi}\",
      \"created_by\": \"$CREATED_BY_LOG\",
      \"gula_version\": \"$VERSION\"
    }
  ],
  \"installed_modules\": {}
}" > .gula.log

    if [ -f ".gula.log" ]; then
        echo "│ ✅ Archivo .gula.log creado exitosamente"
    else
        echo "│ ⚠️ No se pudo crear el archivo .gula.log"
    fi

    echo "│"
    echo "└──────────────────────────────────────────────"

}

