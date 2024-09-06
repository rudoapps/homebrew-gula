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
  NEW_PACKAGE=$(grep '^name:' pubspec.yaml | awk '{print $2}')

  # Verifica si se pudo extraer el nombre
  if [ -z "$NEW_PACKAGE" ]; then
    echo -e "${RED}No se pudo encontrar el nombre del paquete en pubspec.yaml.${NC}"
    exit 1
  fi

  # Define el nombre del paquete antiguo (reemplaza 'antiguo_paquete' por el nombre correcto)
  OLD_PACKAGE="gula"
  echo -e "${YELLOW}Renombrando imports de $OLD_PACKAGE a $NEW_PACKAGE en los archivos del módulo...${NC}"

  # Realiza el reemplazo en todos los archivos .dart dentro del proyecto
  find . -type f -name "*.dart" -exec sed -i "" "s/package:$OLD_PACKAGE\//package:$NEW_PACKAGE\//g" {} +
  
  if [ $? -eq 0 ]; then
    echo -e "✅ Reemplazo completado: $OLD_PACKAGE -> $NEW_PACKAGE"
  else
    echo -e "${RED}Error: No se ha podido renombrar.${NC}"
    remove_temporary_dir
    exit 1
  fi
}


flutter_read_configuration() {
  # Verificar si el fichero existe
  FILE="${TEMPORARY_DIR}/lib/modules/${MODULE_NAME}/configuration.gula"
  
  if [ ! -f "$FILE" ]; then
    echo -e "${RED}Error: El fichero $FILE no existe.${NC}"
    exit 1
  fi

  echo "Lectura correcta de fichero de configuración"
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