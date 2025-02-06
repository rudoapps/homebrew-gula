#!/usr/bin/env bash

# Constantes
ARCH_REPO="https://github.com/rudoapps/ios-archetype"
ARCH_ASP_NAME="rudo_archetype"
ARCH_APP_ID="es.rudo.archetype.swiftui"

# Guardar la ruta de ejecución
execPath=$PWD

# Función de ayuda
helpFun(){
    echo -e "\n\033[1;1m[Uso]\n$0\033[0m"
    echo -e "\n\033[1;1mEste script configurará un nuevo proyecto iOS basado en el arquetipo.\033[0m"
    exit 1
}

# Comprobar el resultado de la ejecución de un paso
checkResult(){
    if [ $? != 0 ]
    then
    echo -e "\n\033[1;31mError:  Paso '$1' FALLÓ \033[0m\n"
    exit 1
    fi
}


ios_create_project() {
    # Pedir parámetros al usuario
    read -p "Introduce la ruta de destino para el nuevo proyecto (por ejemplo, ../NuevaApp): " projectPath
    read -p "Introduce el nombre de la nueva aplicación (opcional, se usará el nombre del repo si se deja vacío): " appName
    read -p "Introduce el identificador base del bundle (por ejemplo, com.mercadona.archetype): " appId

    # Validar parámetros
    if [ -z "$projectPath" ] || [ -z "$appId" ]
    then
    echo -e "\n\033[1;31mError: Faltan parámetros obligatorios \033[0m\n";
    helpFun
    fi

    echo "Iniciando configuración..."

    echo "┌──────────────────────────────────────────────"
    echo "│"
    echo "│ Obteniendo el nombre de la nueva aplicación...\n"
    echo "│ ✅ Nombre de la aplicación encontrado: $appName\n"
    echo "│"
    echo "└──────────────────────────────────────────────"
    echo 
    # Clonar arquetipo
    echo "┌──────────────────────────────────────────────"
    echo "│"
    echo "│ Clonando repositorio de arquetipo iOS: '$ARCH_REPO'..."
    echo "│"
    echo "└──────────────────────────────────────────────"
    git clone $ARCH_REPO --branch main --depth 1 $projectPath
    
    echo "┌──────────────────────────────────────────────"
    echo "│"
    echo "│ " checkResult "Clonando repositorio de arquetipo"
    echo "│"
    echo "│ ✅ Clonado exitosamente"
    echo "│"
    echo "└──────────────────────────────────────────────"
    echo ""
    echo "┌──────────────────────────────────────────────"
    echo "│"
    echo "│ Moviéndose a la ruta: '$execPath/$projectPath'..."
    cd $execPath/$projectPath
    checkResult "│ Moviéndose a la carpeta de la aplicación"
    echo "│ ✅ Movimiento exitoso"
    echo "│"
    echo "└──────────────────────────────────────────────"
    echo ""
    echo "┌──────────────────────────────────────────────"
    echo "│"
    echo "│ Renombrando el directorio ${ARCH_ASP_NAME} a ${appName}..."
    if [ -d "${ARCH_ASP_NAME}" ]; then
        mv ${ARCH_ASP_NAME} ${appName}
        checkResult "Renombrando el directorio ${ARCH_ASP_NAME}"
        echo -e "│ \033[1;32m✅ Renombrado exitoso\033[0m"
    else
        echo -e "│ \033[1;33m[!] El directorio ${appName} no existe. Creando uno nuevo...\033[0m"
        mkdir ${appName}
        checkResult "│ Creando el directorio ${appName}"
        echo -e "│ \033[1;32m✅ Directorio creado exitosamente\033[0m"
    fi
    checkResult "Renombrando el directorio ${ARCH_ASP_NAME}"
    echo "│ ✅ Renombrado exitoso"
    echo "│"
    echo "└──────────────────────────────────────────────"
}
