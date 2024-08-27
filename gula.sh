#!/bin/bash
# source ./private.sh
# Variables
ANDROID_PROJECT_SRC="app/src/main/java"
OLD_PACKAGE="app.gula.com"
TEMPORARY_DIR="temp-gula"
DESTINATION_PROJECT_PATH="/"
MODULES_DIR="modules"
MODULES_PATH="app/src/main/java/app/gula/com/${MODULES_DIR}/"
VERSION="0.0.4"
KEY=""

# Definir colores
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

clone() {
  if [ -d "$TEMPORARY_DIR" ]; then
    rm -rf "$TEMPORARY_DIR"
  fi

  # Clonar el repositorio específico desde Bitbucket en un directorio temporal
  BITBUCKET_REPO_URL="https://x-token-auth:$KEY@bitbucket.org/rudoapps/gula-android.git"
  git clone "$BITBUCKET_REPO_URL" --branch main --single-branch --depth 1 "${TEMPORARY_DIR}"
  if [ $? -eq 0 ]; then
      echo -e "${GREEN}OK.${NC}"
  else
    echo -e "${RED}Se ha producido un error descargando el repositorio.${NC}"
    exit 1
  fi 
  
}

install_module() {
  MODULE_NAME="$1"

  # Ruta del módulo en el proyecto destino
  if [ ! -d "$ANDROID_PROJECT_SRC" ]; then
    echo -e "${RED}Error: No te encuentras en un proyecto Android.${NC}"
    exit 0
  fi

  # STEP1
  # Verificar si la ruta base existe
  echo -e "${YELLOW}STEP1 - Localizar package name del proyecto.${NC}"
  if [ -d "$ANDROID_PROJECT_SRC" ]; then
    # Encontrar el primer directorio que contenga un archivo .java o .kt
    first_directory=$(find "$ANDROID_PROJECT_SRC" -type f \( -name "*.java" -o -name "*.kt" \) -print0 | xargs -0 -n1 dirname | sort -u | head -n 1)
    
    if [ -n "$first_directory" ]; then
      echo -e "${GREEN}OK. Encontrado package: $first_directory${NC}"
    else
      echo -e "${RED}No se encontraron archivos .java o .kt en $ANDROID_PROJECT_SRC${NC}"
    fi
  else
    echo -e "${RED}No se encontró la ruta base en: $ANDROID_PROJECT_SRC${NC}"
  fi

  # Clonamos el repositorio a una carpeta temporal
  echo -e "${YELLOW}STEP2 - Clonación temporal del proyecto de GULA.${NC}"
  clone

  # Verificar que el módulo existe en el repositorio clonado
  echo -e "${YELLOW}STEP3 - Verificación de la existencia del módulo: ${MODULE_NAME}.${NC}"
  if [ ! -d "$TEMPORARY_DIR/${MODULES_PATH}${MODULE_NAME}" ]; then
    echo -e "${RED}Error: El módulo $MODULE_NAME no existe en el repositorio.${NC}"
    echo -e "${RED}No encontrado en: $MODULES_PATH"
    rm -rf "$TEMPORARY_DIR"
    exit 1
  fi
  echo -e "${GREEN}OK.${NC}"

  # Verificar si el módulo ya está instalado en el proyecto destino
  echo -e "${YELLOW}STEP4 - Verificación instalación previa del módulo: ${MODULE_NAME}.${NC}"
  MODULE_PATH="${first_directory}/modules/$MODULE_NAME"
  if [ -d "$MODULE_PATH" ]; then
    echo -e "${YELLOW}El módulo $MODULE_NAME ya existe en el proyecto destino.${NC}"
    read -p "¿Deseas actualizar el módulo existente? (s/n): " CONFIRM
    if [ "$CONFIRM" != "s" ]; then
      echo "  Instalación del módulo cancelada."
      exit 0
    fi
    echo -e "${GREEN}OK.${NC}"
    # Eliminar el módulo existente antes de actualizarlo
    rm -rf "$MODULE_PATH"
  else 
    echo -e "${GREEN}OK.${NC}"
  fi
  
  # Verificar si la carpeta 'modules' existe; si no, crearla
  echo -e "${YELLOW}STEP5 - Verificación existencia carpeta: ${MODULE_NAME}.${NC}"
  EXISTS_THIS_DIR=${first_directory}/modules/${MODULE_NAME}
  if [ ! -d "$EXISTS_THIS_DIR" ]; then
    echo -e "${YELLOW}La carpeta '${MODULE_NAME}' no existe. Creándola...${NC}"
    mkdir -p "$EXISTS_THIS_DIR"
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}OK.${NC}"
    else
      echo -e "${RED}Error: No se pudo crear la carpeta '${MODULE_NAME}'.${NC}"
      exit 1
    fi 
  fi

  # Copiar el módulo al proyecto destino
  echo -e "${YELLOW}STEP6 - Copiar ficheros al proyecto.${NC}"
  echo -e "${YELLOW}Inicio copiado de del módulo ${MODULE_NAME} en: ${first_directory}/modules/${MODULE_NAME}${NC}"
  cp -R "${TEMPORARY_DIR}/${MODULES_PATH}${MODULE_NAME}" "${first_directory}/modules/"
  # Validar si el comando se ejecutó correctamente
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}OK.${NC}"
  else
    echo -e "${RED}Error: No se ha podido copiar el módulo.${NC}"
    rm -rf "$TEMPORARY_DIR"
    exit 1
  fi

 
  # Eliminar el string especificado de la ruta
  REMOVE_PATH=$ANDROID_PROJECT_SRC
  MODIFIED_PATH=$(echo "$first_directory" | sed "s|$REMOVE_PATH||")
  PACKAGE_NAME=$(echo "$MODIFIED_PATH" | sed 's|/|.|g')
  PACKAGE_NAME="${PACKAGE_NAME/.}"

   # Renombrar los imports en los archivos .java y .kt del módulo copiado
  echo -e "${YELLOW}STEP7 - Renombrar imports.${NC}"
  echo -e "${YELLOW}Renombrando imports de $OLD_PACKAGE a $PACKAGE_NAME en los archivos del módulo...${NC}"

  find "$first_directory" -type f \( -name "*.java" -o -name "*.kt" \) -print0 | while IFS= read -r -d '' file; do
    sed -i '' "s#$OLD_PACKAGE#$PACKAGE_NAME#g" "$file"
  done
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}OK.${NC}"
  else
    echo -e "${RED}Error: No se ha podido renombrar.${NC}"
    rm -rf "$TEMPORARY_DIR"
    exit 1
  fi
  echo -e "${YELLOW}STEP8 - Eliminación repositorio temporal.${NC}"
  rm -rf "$TEMPORARY_DIR"
  echo -e "${GREEN}OK.${NC}"
  
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

MODULE_NAME=""
KEY=""

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