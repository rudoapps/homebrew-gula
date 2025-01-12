#!/usr/bin/env bash

# Constantes
ARCH_REPO="https://github.com/rudoapps/ios-archetype"
ARCH_ASP_NAME="rudo_archetype"
ARCH_APP_ID="es.rudo.archetype.swiftui"

# Guardar la ruta de ejecución
execPath=$PWD

# Función de ayuda
helpFun(){
    echo -e "\n\033[1;1m[Uso]\n$0 -d <ruta_destino_proyecto> -g <repo_git> -b <id_bundle> -v <version_arquetipo> -u <nombre_usuario> -e <email_usuario>\033[0m"
    echo -e "\n\033[1;1m[Parámetros]\033[0m"
    echo -e "\033[1;1m\t-d\tRuta de destino para el nuevo proyecto. El arquetipo se clonará en esta ruta. Ejemplo: '../NuevaApp'\033[0m"
    echo -e "\033[1;1m\t-g\tLa URL del repositorio GIT para esta nueva aplicación.\033[0m"
    echo -e "\033[1;1m\t-n\tNombre de la nueva aplicación (opcional). Ejemplo: 'NuevaApp'\033[0m"
    echo -e "\033[1;1m\t-b\tEl identificador base del bundle. Ejemplo: 'com.mercadona.archetype'\033[0m"
    echo -e "\033[1;1m\t-v\tLa versión base del arquetipo (opcional). Ejemplo: '1.0.0'\n\033[0m"
    echo -e "\033[1;1m\t-u\tEl nombre del autor para el repositorio git. Ejemplo: 'Nombre Ejemplo'\n\033[0m"
    echo -e "\033[1;1m\t-e\tEl email del autor para el repositorio git. Ejemplo: 'ejemplo@mercadona.com'\n\033[0m"
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
    # Leer parámetros
    while getopts "d:g:n:b:v:u:e:" opt
    do
    case "$opt" in
    d     ) projectPath="$OPTARG" ;;
    g     ) gitRepo="$OPTARG" ;;
    n    ) appName="$OPTARG" ;;
    b     ) appId="$OPTARG" ;;
    v    ) archVersion="$OPTARG" ;;
    u    ) userName="$OPTARG" ;;
    e    ) userEmail="$OPTARG" ;;
    ?     ) helpFun ;;
    esac
    done

    # Mostrar ayuda si falta algún parámetro
    if [ -z "$projectPath" ] || [ -z "$appId" ]
    then
    echo -e "\n\033[1;31m[✘] Faltan parámetros obligatorios \033[0m\n";
    helpFun
    fi
    echo -e "\n\033[1;34mIniciando configuración... \033[0m"

    # Obtener el nombre de la aplicación
    echo -e "\033[1;34m==> Obteniendo el nombre de la nueva aplicación...\033[0m\n"
    if [ -z "$appName" ]; then
    if [[ $gitRepo =~ ^.*\/(.*)\.git$ ]]; then
    appName=${BASH_REMATCH[1]}
    else
    echo -e "\n\033[1;31m[✘] Nombre de aplicación no válido \033[0m\n"
    echo -e "\n033[1;31m[✘] Paso FALLÓ \033[0m\n"

    exit 1
    fi
    fi
    echo -e "\033[1;32m✅ Nombre de la aplicación encontrado: $appName\n\033[0m"

    # Clonar arquetipo
    echo -e "\033[1;34m==> Clonando repositorio de arquetipo iOS: '$ARCH_REPO' $archVersion...\033[0m"
    if [ -z "$archVersion" ]
    then
    git clone $ARCH_REPO --branch master --depth 1 $projectPath
    else
    git clone $ARCH_REPO --branch $archVersion --depth 1 $projectPath
    fi
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
