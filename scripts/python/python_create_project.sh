#!/usr/bin/env bash

# Constantes
ARCH_REPO="bitbucket.org:rudoapps/architecture-python.git"
execPath=$PWD


get_token() {
    echo "┌──────────────────────────────────────────────"
    echo "│"
    echo "│ Validando key"
    echo "│ "
    echo "└──────────────────────────────────────────────"   
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
        echo "┌──────────────────────────────────────────────"
        echo "│"
        echo "│ ❌ Error: Paso '$1' FALLÓ."
        echo "│"
        echo "└──────────────────────────────────────────────" 
    exit 1
    fi
}

validate_project_name() {
    if [[ -z "$projectPath" || "$projectPath" =~ ^[[:space:]]*$ ]]; then
        echo "┌──────────────────────────────────────────────"
        echo "│"
        echo "│ ❌ Error: El nombre del proyecto no puede estar vacío ni ser solo espacios."
        echo "│"
        echo "└──────────────────────────────────────────────"  
        exit 1
    fi

    # Validar caracteres válidos (letras, números, guiones y guiones bajos)
    if [[ ! "$projectPath" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "┌──────────────────────────────────────────────"
        echo "│"
        echo "│ ❌ Error: El nombre del proyecto contiene caracteres no válidos."
        echo "│ ✅ Usa solo letras, números, guiones (-), guiones bajos (_) y puntos (.)"
        echo "│"
        echo "└──────────────────────────────────────────────" 
        exit 1
    fi
}

python_create_project() {
    read -p "Introduce la ruta de destino para el nuevo proyecto (por ejemplo, ../NuevaApp): " projectPath
    validate_project_name

    if [ -z "$projectPath" ]; then
        echo "┌──────────────────────────────────────────────"
        echo "│"
        echo "│ ❌  Error: Faltan parámetros obligatorios."
        echo "│"
        echo "└──────────────────────────────────────────────"  
        helpFun
        exit 1
    fi

    if [ -d "$projectPath" ]; then
        echo "┌──────────────────────────────────────────────"
        echo "│"
        echo "│ ❌  La carpeta '$projectPath' ya existe. Por seguridad no se sobrescribirá."
        echo "│"
        echo "└──────────────────────────────────────────────"        
        exit 1
    fi

    # Carpeta temporal
    TEMP_CLONE_DIR="temp-archetype"
    if [ -d "$TEMP_CLONE_DIR" ]; then
        echo "┌──────────────────────────────────────────────"
        echo "│"
        echo "│ 🗑️  Eliminando carpeta temporal existente: $TEMP_CLONE_DIR"
        echo "│"
        echo "└──────────────────────────────────────────────"   
        rm -rf "$TEMP_CLONE_DIR"
    fi
    
    get_token

    echo "┌──────────────────────────────────────────────"
    echo "│"
    echo "│ ✅ Clonando arquetipo en carpeta temporal..."
    echo "│"
    echo "└──────────────────────────────────────────────"

    git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/python-archetype.git" "$TEMP_CLONE_DIR"
    checkResult "Clonando repositorio arquetipo"

    echo "┌──────────────────────────────────────────────"
    echo "│"
    echo "│ ✅ Eliminando .git para limpiar el historial..."
    echo "│"
    echo "└──────────────────────────────────────────────"
    rm -rf "$TEMP_CLONE_DIR/.git"

    echo "┌──────────────────────────────────────────────"
    echo "│"
    echo "│ ✅ Copiando contenido en: '$projectPath'..."
    echo "│"
    echo "└──────────────────────────────────────────────"

    mkdir -p "$projectPath"
    cp -R "$TEMP_CLONE_DIR"/. "$projectPath"
    checkResult "Copiando contenido del arquetipo"

    echo "┌──────────────────────────────────────────────"
    echo "│"
    echo "│ ✅ Eliminando carpeta temporal..."
    echo "│"
    echo "└──────────────────────────────────────────────"

    rm -rf "$TEMP_CLONE_DIR"

    echo "┌──────────────────────────────────────────────"
    echo "│"
    echo "│ Moviéndose a la carpeta del proyecto..."
     cd "$projectPath"
    checkResult  "│ Moviéndose a la carpeta del proyecto"

    echo "│ ✅ Ruta absoluta: $(pwd)"
    echo "│"
    echo "└──────────────────────────────────────────────"
   
}

