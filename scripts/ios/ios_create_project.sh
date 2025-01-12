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
    echo -e "\n\033[1;31m[✘] Paso '$1' FALLÓ \033[0m\n"
    exit 1
    fi
}

# Comprobar el resultado de la ejecución de un paso (opcional)
optionalCheckResult(){
    if [ $? != 0 ]
    then
    echo -e "\n\033[1;31m[✘] Paso '$1' FALLÓ \033[0m\n"
    echo -e "\nContinuando...\n"
    fi
}

pause(){
    read -p "Presiona [Enter] para continuar..."
}

ios_create_project() {
    # Pedir parámetros al usuario
    read -p "Introduce la ruta de destino para el nuevo proyecto (por ejemplo, ../NuevaApp): " projectPath
    read -p "Introduce el nombre de la nueva aplicación (opcional, se usará el nombre del repo si se deja vacío): " appName
    read -p "Introduce el identificador base del bundle (por ejemplo, com.mercadona.archetype): " appId
    read -p "Introduce el nombre del autor para el repositorio git: " userName
    read -p "Introduce el email del autor para el repositorio git: " userEmail

    # Validar parámetros
    if [ -z "$projectPath" ] || [ -z "$appId" ]
    then
    echo -e "\n\033[1;31m[✘] Faltan parámetros obligatorios \033[0m\n";
    helpFun
    fi

    echo -e "\n\033[1;34mIniciando configuración... \033[0m"

    # Obtener el nombre de la aplicación
    echo -e "\033[1;34m==> Obteniendo el nombre de la nueva aplicación...\033[0m\n"
    echo -e "\033[1;32m✅ Nombre de la aplicación encontrado: $appName\n\033[0m"

    # Clonar arquetipo
    echo -e "\033[1;34m==> Clonando repositorio de arquetipo iOS: '$ARCH_REPO'...\033[0m"
 
    git clone $ARCH_REPO --branch master --depth 1 $projectPath
    
    checkResult "Clonando repositorio de arquetipo"
    echo -e "\033[1;32m✅ Clonado exitosamente\n\033[0m"

    # Cambiar al directorio de la nueva aplicación
    echo -e "\033[1;34m==> Moviéndose a la ruta: '$execPath/$projectPath'...\033[0m"
    cd $execPath/$projectPath
    checkResult "Moviéndose a la carpeta de la aplicación"
    echo -e "\033[1;32m✅ Movimiento exitoso\033[0m"

    # Renombrar directorio principal del target
    echo -e "\033[1;34m==> Renombrando el directorio ${ARCH_ASP_NAME} a ${appName}...\033[0m"
    mv ${ARCH_ASP_NAME} ${appName}
    checkResult "Renombrando el directorio ${ARCH_ASP_NAME}"
    echo -e "\033[1;32m✅ Renombrado exitoso\033[0m"

    # Continuar con el resto del script...
}

# Llamar a la función principal
ios_create_project "$@"
