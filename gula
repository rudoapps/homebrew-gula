#!/bin/bash
# source ./private.sh
# Variables
ANDROID_PROJECT_SRC="app/src/main/java"
OLD_PACKAGE="app.gula.com"
TEMPORARY_DIR="temp-gula"
DESTINATION_PROJECT_PATH="/"
MODULES_DIR="modules"
MODULES_PATH="app/src/main/java/app/gula/com/${MODULES_DIR}/"
KEY=""

# Definir colores
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

clone() {
  # Clonar el repositorio específico desde Bitbucket en un directorio temporal
  BITBUCKET_REPO_URL="https://x-token-auth:$KEY@bitbucket.org/rudoapps/gula-android.git"
  git clone "$BITBUCKET_REPO_URL" --branch main --single-branch --depth 1 "${TEMPORARY_DIR}"
}

install_module() {
  MODULE_NAME="$1"

  # Ruta del módulo en el proyecto destino
  if [ ! -d "$ANDROID_PROJECT_SRC" ]; then
    echo -e "${RED}Error: No te encuentras en un proyecto Android.${NC}"
    exit 0
  fi

  # Verificar si la ruta base existe
  if [ -d "$ANDROID_PROJECT_SRC" ]; then
    # Encontrar el primer directorio que contenga un archivo .java o .kt
    first_directory=$(find "$ANDROID_PROJECT_SRC" -type f \( -name "*.java" -o -name "*.kt" \) -print0 | xargs -0 -n1 dirname | sort -u | head -n 1)
    
    if [ -n "$first_directory" ]; then
      echo -e "${GREEN}El primer directorio que contiene un archivo .java o .kt es: $first_directory${NC}"
    else
      echo -e "${RED}No se encontraron archivos .java o .kt en $ANDROID_PROJECT_SRC${NC}"
    fi
  else
    echo -e "${RED}No se encontró la ruta base en: $ANDROID_PROJECT_SRC${NC}"
  fi

  clone

  # Verificar que el módulo existe en el repositorio clonado
  if [ ! -d "$TEMPORARY_DIR/${MODULES_PATH}${MODULE_NAME}" ]; then
    echo -e "${RED}Error: El módulo $MODULE_NAME no existe en el repositorio.${NC}"
    echo -e "${RED}No encontrado en: $MODULES_PATH"
    rm -rf "$TEMPORARY_DIR"
    exit 1
  fi

  # Verificar si el módulo ya está instalado en el proyecto destino
  MODULE_PATH="${first_directory}/modules/$MODULE_NAME"
  if [ -d "$MODULE_PATH" ]; then
    echo "El módulo $MODULE_NAME ya existe en el proyecto destino."
    read -p "¿Deseas actualizar el módulo existente? (s/n): " CONFIRM
    if [ "$CONFIRM" != "s" ]; then
      echo "Instalación del módulo cancelada."
      exit 0
    fi
    # Eliminar el módulo existente antes de actualizarlo
    rm -rf "$MODULE_PATH"
  fi

  # Verificar si la carpeta 'modules' existe; si no, crearla
  EXISTS_THIS_DIR=${first_directory}/modules/${MODULE_NAME}
  if [ ! -d "$EXISTS_THIS_DIR" ]; then
    echo "La carpeta '${MODULE_NAME}' no existe. Creándola..."
    mkdir -p "$EXISTS_THIS_DIR"
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}Carpeta '${MODULE_NAME}' creada correctamente.${NC}"
    else
      echo -e "${RED}Error: No se pudo crear la carpeta '${MODULE_NAME}'.${NC}"
      exit 1
    fi 
  fi

  # Copiar el módulo al proyecto destino
  echo "Inicio copiado de del módulo ${MODULE_NAME} en: ${first_directory}/modules/${MODULE_NAME}"
  cp -R "${TEMPORARY_DIR}/${MODULES_PATH}${MODULE_NAME}" "${first_directory}/modules/"
  # Validar si el comando se ejecutó correctamente
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copiado el modulo ${MODULE_NAME} correctamente.${NC}"
  else
    echo -e "${RED}Error: No se ha podido copiar el módulo.${NC}"
    rm -rf "$TEMPORARY_DIR"
    exit 1
  fi

  # Renombrar los imports en los archivos .java y .kt del módulo copiado
  echo "Renombrando imports de $OLD_PACKAGE a $NEW_PACKAGE en los archivos del módulo..."
  # Eliminar el string especificado de la ruta
  REMOVE_PATH=$ANDROID_PROJECT_SRC
  MODIFIED_PATH=$(echo "$first_directory" | sed "s|$REMOVE_PATH||")
  PACKAGE_NAME=$(echo "$MODIFIED_PATH" | sed 's|/|.|g')
  PACKAGE_NAME="${PACKAGE_NAME/.}"

  find "$first_directory" -type f \( -name "*.java" -o -name "*.kt" \) -print0 | while IFS= read -r -d '' file; do
    sed -i '' "s#$OLD_PACKAGE#$PACKAGE_NAME#g" "$file"
  done
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Renombrado de imports completado.${NC}"
  else
    echo -e "${RED}Error: No se ha podido renombrar.${NC}"
    rm -rf "$TEMPORARY_DIR"
    exit 1
  fi


  # Verificar si existe el archivo de dependencias en el módulo
  DEPENDENCIES_FILE="$TEMPORARY_DIR/$MODULE_NAME/module_dependencies.gradle"
  if [ -f "$DEPENDENCIES_FILE" ]; then
    echo "Validando y agregando dependencias del módulo al build.gradle del proyecto destino..."
    # Leer el archivo de dependencias
    while read -r line; do
      # Solo agregar líneas de dependencias (ignorando las líneas que no comienzan con 'implementation', 'api', etc.)
      if [[ $line =~ ^(implementation|api|compile|runtimeOnly|testImplementation|androidTestImplementation) ]]; then
        # Verificar si la dependencia ya existe en el build.gradle del proyecto destino
        if ! grep -q "$line" "$DESTINATION_PROJECT_PATH/build.gradle"; then
          # Si no existe, agregarla
          echo "$line" >> "$DESTINATION_PROJECT_PATH/build.gradle"
        else
          echo "Dependencia '$line' ya existe en el build.gradle, no se agregó nuevamente."
        fi
      fi
    done < "$DEPENDENCIES_FILE"
  fi

  # Eliminar el repositorio temporal
  rm -rf "$TEMPORARY_DIR"

  # Modificar el archivo settings.gradle del proyecto destino
  if ! grep -q "include ':$MODULE_NAME'" "$DESTINATION_PROJECT_PATH/settings.gradle"; then
    echo "include ':$MODULE_NAME'" >> "$DESTINATION_PROJECT_PATH/settings.gradle"
  else
    echo "El módulo $MODULE_NAME ya estaba incluido en settings.gradle."
  fi

  echo "Módulo $MODULE_NAME copiado y configurado correctamente en el proyecto destino. Repositorio temporal eliminado."
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