#!/bin/bash

# Variables
ANDROID_PROJECT_RES="app/src/main/res"
ANDROID_PROJECT_SRC="app/src/main/java"
GULA_PACKAGE="app.gula.com"
TEMPORARY_DIR="temp-gula"
GULA_PROJECT_ROOT="app/src/main/java/app/gula/com/"
MODULES_DIR="modules"
MODULES_PATH="app/src/main/java/app/gula/com/${MODULES_DIR}/"
MODULES_PATH_IOS="Gula/${MODULES_DIR}"
MODULE_NAME=""
KEY=""
VERSION="0.0.4"

# Definir colores 
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

source ./steps.sh
source ./operations.sh
source ./platform/android.sh
source ./platform/ios.sh

install_module() {
  check_type_of_project
  type=$?

  if [ $type -eq 0 ]; then
    echo -e "${GREEN}Te encuentras en un proyecto Android${NC}"
    install_android_module
  elif [ $type -eq 1 ]; then
    echo -e "${GREEN}Te encuentras en un proyecto IOS${NC}"
    install_ios_module
  else 
    echo -e "${RED}Error: No te encuentras en un proyecto Android/IOS/Flutter.${NC}"
    exit 0
  fi
}

list_modules() {
  check_type_of_project
  type=$?

  if [ $type -eq 0 ]; then
    echo -e "${GREEN}Te encuentras en un proyecto Android${NC}"
    list_android
  elif [ $type -eq 1 ]; then
    echo -e "${GREEN}Te encuentras en un proyecto IOS${NC}"
    list_ios
  else 
    echo -e "${RED}Error: No te encuentras en un proyecto Android/IOS/Flutter.${NC}"
    exit 0
  fi
}

echo -e "${BOLD}-----------------------------------------------"
echo -e "${BOLD}GULA: Instalador de módulos"
echo -e "${BOLD}versión: ${VERSION}"
echo -e "${BOLD}propiedad: Rudo apps"
echo -e "${BOLD}-----------------------------------------------${NC}"
# Verificar que se haya pasado un comando válido
if [ -z "$1" ]; then
  echo "Uso: $0 {install|list} [nombre-del-modulo]"
  exit 1
fi

COMMAND="$1"
shift

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --key=*)
      KEY="${1#*=}"
      ;;
    install)
      COMMAND="install"
      MODULE_NAME="$2"
      shift
      ;;
    list)
      COMMAND="list"
      ;;
    *)
      MODULE_NAME="$1"
      ;;
  esac
  shift
done

# Verificar y ejecutar el comando correspondiente
if [ "$COMMAND" == "install" ]; then
  if [ -z "$MODULE_NAME" ]; then
    echo "Uso: $0 install <module_name> [--key=xxxx]"
    exit 1
  fi
  echo "Comando: $COMMAND"
  echo "Módulo: $MODULE_NAME"
  echo "Clave: $KEY"
  install_module
elif [ "$COMMAND" == "list" ]; then
  echo "Comando: $COMMAND"
  echo "Clave: $KEY"
  list_modules
else
  echo "Comando no reconocido. Uso: $0 {install|list} [--key=xxxx]"
  exit 1
fi