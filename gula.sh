#!/bin/bash

# Variables
TEMPORARY_DIR="temp-gula"
MODULE_NAME=""
KEY=""
ACCESSTOKEN=""
VERSION="0.0.19"

# Definir colores 
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}-----------------------------------------------"
echo -e "${BOLD}GULA: Instalador de módulos"
echo -e "${BOLD}versión: ${VERSION}"
echo -e "${BOLD}propiedad: Rudo apps"
echo -e "${BOLD}-----------------------------------------------${NC}"
echo ""
echo -e "${BOLD}Cargando imports...${NC}"

HOMEBREW_PREFIX=$(brew --prefix)
scripts_dir="$HOMEBREW_PREFIX/share/support/scripts/scripts"
scripts_dir="../scripts"
echo -e "${BOLD}Ruta de homebrew: $scripts_dir.${NC}"
source "$scripts_dir/android/android.sh"
source "$scripts_dir/android/android_support.sh"
source "$scripts_dir/ios/ios.sh"
source "$scripts_dir/ios/ios_support.sh"
source "$scripts_dir/flutter/flutter.sh"
source "$scripts_dir/flutter/flutter_support.sh"
source "$scripts_dir/support/general_support.sh"
source "$scripts_dir/support/git.sh"
source "$scripts_dir/support/network.sh"
source "$scripts_dir/support/os.sh"
echo -e "✅"

function cleanup {
    remove_temporary_dir
    echo "clean"
}

# Asociar la señal SIGINT (Ctrl + C) con la función cleanup
trap cleanup SIGINT

install_module() {
  check_type_of_project
  type=$?

  if [ $type -eq 0 ]; then
    echo -e "${GREEN}Te encuentras en un proyecto Android${NC}"
    install_android_module
  elif [ $type -eq 1 ]; then
    echo -e "${GREEN}Te encuentras en un proyecto IOS${NC}"
    install_ios_module
  elif [ $type -eq 2 ]; then
    echo -e "${GREEN}Te encuentras en un proyecto Flutter${NC}"
    install_flutter_module
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
  elif [ $type -eq 2 ]; then
    echo -e "${GREEN}Te encuentras en un proyecto Flutter${NC}"
    list_flutter
  else 
    echo -e "${RED}Error: No te encuentras en un proyecto Android/IOS/Flutter.${NC}"
    exit 0
  fi
}


# Verificar que se haya pasado un comando válido
if [ -z "$1" ]; then
  echo "Uso: $0 {install|list} [nombre-del-modulo]"
  exit 1
fi

# Procesar los argumentos
COMMAND="$1"
shift

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --key=*)
      KEY="${1#*=}"
      ;;
    install)
      COMMAND="install"
      MODULE_NAME="$(echo "${str:0:1}" | tr '[:lower:]' '[:upper:]')${str:1}" "$2"

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

if [ "$COMMAND" == "install" ]; then
  if [ -z "$MODULE_NAME" ]; then
    echo "Uso: $0 install <module_name> [--key=xxxx]"
    exit 1
  fi
  install_module "$MODULE_NAME"
elif [ "$COMMAND" == "list" ]; then
  list_modules
else
  echo "Comando no reconocido. Uso: $0 {install|list} [--key=xxxx]"
  exit 1
fi