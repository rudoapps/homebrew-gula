#!/bin/bash

# Variables
ANDROID_PROJECT_SRC="app/src/main/java"
GULA_PACKAGE="app.gula.com"
TEMPORARY_DIR="temp-gula"
MODULES_DIR="modules"
MODULES_PATH="app/src/main/java/app/gula/com/${MODULES_DIR}/"
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

install_module() {
  MODULE_NAME="$1"

  check_is_android

  echo -e "${YELLOW}STEP1 - Localizar package name del proyecto.${NC}"
  detect_package_name

  echo -e "${YELLOW}STEP2 - Clonación temporal del proyecto de GULA.${NC}"
  clone

  echo -e "${YELLOW}STEP3 - Verificación de la existencia del módulo: ${MODULE_NAME}.${NC}"
  check_module_in_temporary_dir

  echo -e "${YELLOW}STEP4 - Verificación instalación previa del módulo: ${MODULE_NAME}.${NC}"
  verify_module
  
  echo -e "${YELLOW}STEP5 - Verificación existencia carpeta: ${MODULE_NAME}.${NC}"
  create_modules_dir

  echo -e "${YELLOW}STEP6 - Copiar ficheros al proyecto.${NC}"
  copy_files

  echo -e "${YELLOW}STEP7 - Renombrar imports.${NC}"
  rename_imports

  echo -e "${YELLOW}STEP8 - Eliminación repositorio temporal.${NC}"
  remove_temporary_dir
  
  echo -e "${GREEN}-----------------------------------------------${NC}"
  echo -e "${GREEN}Proceso finalizado.${NC}"
  echo -e "${GREEN}-----------------------------------------------${NC}"
}

# Función para listar los directorios
list_directories() {
  clone
  DIRECTORY_PATH="${TEMPORARY_DIR}/${MODULES_PATH}"
  echo -e "${GREEN}Lista de módulos disponibles:"
  ls -l "$DIRECTORY_PATH" | grep '^d' | awk '{print $9}'
  echo -e "${NC}"
  rm -rf "$TEMPORARY_DIR"
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

if [ "$COMMAND" == "install" ]; then
  if [ -z "$MODULE_NAME" ]; then
    echo "Uso: $0 install <module_name> [--key=xxxx]"
    exit 1
  fi
  install_module "$MODULE_NAME"
elif [ "$COMMAND" == "list" ]; then
  list_directories
else
  echo "Comando no reconocido. Uso: $0 {install|list} [--key=xxxx]"
  exit 1
fi