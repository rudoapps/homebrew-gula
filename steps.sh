#!/bin/bash

MAIN_DIRECTORY=""

# Ruta del módulo en el proyecto destino
check_is_android() {
  if [ ! -d "$ANDROID_PROJECT_SRC" ]; then
    echo -e "${RED}Error: No te encuentras en un proyecto Android.${NC}"
    exit 0
  fi
}

detect_package_name() {
  if [ -d "$ANDROID_PROJECT_SRC" ]; then
    # Encontrar el primer directorio que contenga un archivo .java o .kt
    MAIN_DIRECTORY=$(find "$ANDROID_PROJECT_SRC" -type f \( -name "*.java" -o -name "*.kt" \) -print0 | xargs -0 -n1 dirname | sort -u | head -n 1)
    
    if [ -n "$MAIN_DIRECTORY" ]; then
      echo -e "${GREEN}OK. Encontrado package: $MAIN_DIRECTORY${NC}"
    else
      echo -e "${RED}No se encontraron archivos .java o .kt en $ANDROID_PROJECT_SRC${NC}"
    fi
  else
    echo -e "${RED}No se encontró la ruta base en: $ANDROID_PROJECT_SRC${NC}"
  fi
}

clone() {
  remove_temporary_dir
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

check_module_in_temporary_dir() {
  if [ ! -d "$TEMPORARY_DIR/${MODULES_PATH}${MODULE_NAME}" ]; then
    echo -e "${RED}Error: El módulo $MODULE_NAME no existe en el repositorio.${NC}"
    echo -e "${RED}No encontrado en: $MODULES_PATH"
    rm -rf "$TEMPORARY_DIR"
    exit 1
  fi
  echo -e "${GREEN}OK.${NC}"
}

verify_module() {
  MODULE_PATH="${MAIN_DIRECTORY}/modules/$MODULE_NAME"
  if [ -d "$MODULE_PATH" ]; then
    echo -e "${YELLOW}El módulo $MODULE_NAME ya existe en el proyecto destino.${NC}"
    read -p "¿Deseas actualizar el módulo existente? (s/n): " CONFIRM
    if [ "$CONFIRM" != "s" ]; then
      echo "  Instalación del módulo cancelada."
      exit 0
    fi
    rm -rf "$MODULE_PATH"
    echo -e "${GREEN}OK.${NC}"
  else 
    echo -e "${GREEN}OK.${NC}"
  fi
}

create_modules_dir() {
  EXISTS_THIS_DIR=${MAIN_DIRECTORY}/modules/${MODULE_NAME}
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
}

copy_files() {
  echo -e "${YELLOW}Inicio copiado de del módulo ${MODULE_NAME} en: ${MAIN_DIRECTORY}/modules/${MODULE_NAME}${NC}"
  cp -R "${TEMPORARY_DIR}/${MODULES_PATH}${MODULE_NAME}" "${MAIN_DIRECTORY}/modules/"
  # Validar si el comando se ejecutó correctamente
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}OK.${NC}"
  else
    echo -e "${RED}Error: No se ha podido copiar el módulo.${NC}"
    remove_temporary_dir
    exit 1
  fi
}

rename_imports() {
  # Eliminar el string especificado de la ruta
  echo -e "${YELLOW}Renombrando imports de $GULA_PACKAGE a $PACKAGE_NAME en los archivos del módulo...${NC}"
  REMOVE_PATH=$ANDROID_PROJECT_SRC
  MODIFIED_PATH=$(echo "$MAIN_DIRECTORY" | sed "s|$REMOVE_PATH||")
  PACKAGE_NAME=$(echo "$MODIFIED_PATH" | sed 's|/|.|g')
  PACKAGE_NAME="${PACKAGE_NAME/.}"
  find "$MAIN_DIRECTORY" -type f \( -name "*.java" -o -name "*.kt" \) -print0 | while IFS= read -r -d '' file; do
    sed -i '' "s#$GULA_PACKAGE#$PACKAGE_NAME#g" "$file"
  done
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}OK.${NC}"
  else
    echo -e "${RED}Error: No se ha podido renombrar.${NC}"
    remove_temporary_dir
    exit 1
  fi
}

remove_temporary_dir() {
  if [ -d "$TEMPORARY_DIR" ]; then
    rm -rf "$TEMPORARY_DIR"
  fi
  echo -e "${GREEN}OK.${NC}"
}