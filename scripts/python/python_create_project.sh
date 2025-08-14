#!/usr/bin/env bash

# Constantes
execPath=$PWD


get_token() {
    echo ""
    echo "┌──────────────────────────────────────────────"  
    echo "│"
    echo "│ Validando key"
    echo "│ "
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

    case "$STACK" in
      fastapi)
        BRANCH="fastapi"
        ;;
      django)
        BRANCH="main"
        ;;
    esac

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
    echo "│ ✅ Eliminando carpeta temporal..."


    rm -rf "$TEMP_CLONE_DIR"

    echo "│"
    echo "│ 👍 Proyecto python preparado en: $(pwd)"
    echo "│"
    echo "└──────────────────────────────────────────────"
   
}

