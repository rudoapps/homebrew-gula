#!/bin/bash

flutter_create_modules_dir() {
  EXISTS_THIS_DIR=lib/modules/${MODULE_NAME}
  if [ ! -d "$EXISTS_THIS_DIR" ]; then
    echo -e "${YELLOW}La carpeta '${MODULE_NAME}' no existe. Creándola...${NC}"
    mkdir -p "$EXISTS_THIS_DIR"
    if [ $? -eq 0 ]; then
      echo -e "✅"
    else
      echo -e "${RED}Error: No se pudo crear la carpeta '${MODULE_NAME}'.${NC}"
      exit 1
    fi 
  fi
}


flutter_rename_imports() {
  # Eliminar el string especificado de la ruta
  REMOVE_PATH=$ANDROID_PROJECT_SRC
  MODIFIED_PATH=$(echo "$MAIN_DIRECTORY" | sed "s|$REMOVE_PATH||")
  PACKAGE_NAME=$(echo "$MODIFIED_PATH" | sed 's|/|.|g')
  PACKAGE_NAME="${PACKAGE_NAME/.}"
  echo -e "${YELLOW}Renombrando imports de $GULA_PACKAGE a $PACKAGE_NAME en los archivos del módulo...${NC}"

  find "$MAIN_DIRECTORY" -type f \( -name "*.java" -o -name "*.kt" \) -print0 | while IFS= read -r -d '' file; do
    sed -i '' "s#$GULA_PACKAGE#$PACKAGE_NAME#g" "$file"
  done
  if [ $? -eq 0 ]; then
    echo -e "✅"
  else
    echo -e "${RED}Error: No se ha podido renombrar.${NC}"
    remove_temporary_dir
    exit 1
  fi
}


flutter_read_configuration() {
  # Verificar si el fichero existe
  FILE="${TEMPORARY_DIR}/lib/modules/${MODULE_NAME}/configuration.gula"
  echo $FILE
  if [ ! -f "$FILE" ]; then
    echo "Error: El fichero $FILE no existe."
    exit 1
  fi

  # Leer el fichero línea por línea
  while IFS= read -r line; do
    # Extraer el tipo (assets, strings, colors, dimens)
    type=$(echo "$line" | cut -d'/' -f1)
    
    # Extraer la parte de la ruta a transformar
    # path=$(echo "$line" | cut -d'/' -f2-)
    path=$(dirname "$line")
    EXISTS_THIS_DIR=lib/${path}
    if [ ! -d "$EXISTS_THIS_DIR" ]; then
      echo -e "${YELLOW}La carpeta '${path}' no existe. Creándola...${NC}"
      mkdir -p "$EXISTS_THIS_DIR"
      if [ $? -eq 0 ]; then
        echo -e "✅"
      else
        echo -e "${RED}Error: No se pudo crear la carpeta '${MODULE_NAME}'.${NC}"
        exit 1
      fi 
    fi
    copy_files "${TEMPORARY_DIR}/lib/${line}" "lib/${line}"
    
  done < "$FILE"
}