#!/bin/bash

MAIN_DIRECTORY=""

check_type_of_project() {
  if [ -d "$ANDROID_PROJECT_SRC" ]; then
      return 0
    elif find . -maxdepth 1 -name "*.xcodeproj" | grep -q .; then
      return 1 
    elif [ -f "pubspec.yaml" ]; then
      return 2 
    else
      return -1
    fi
}

check_module_in_temporary_dir() {
  if [ ! -d "$TEMPORARY_DIR/${MODULES_PATH}${MODULE_NAME}" ]; then
    echo -e "${RED}Error: El módulo $MODULE_NAME no existe en el repositorio.${NC}"
    echo -e "${RED}No encontrado en: $MODULES_PATH"
    rm -rf "$TEMPORARY_DIR"
    exit 1
  fi
  echo -e "✅"
}

copy_files() {
  local origin=$1
  local destination=$2
  
  echo "Copiand de ${1} a ${2}"
  cp -R $1 $2
  # Validar si el comando se ejecutó correctamente
  if [ $? -eq 0 ]; then
    echo -e "✅"
  else
    echo -e "${RED}Error: No se ha podido copiar.${NC}"
    remove_temporary_dir
    exit 1
  fi
}

remove_temporary_dir() {
  if [ -d "$TEMPORARY_DIR" ]; then
    rm -rf "$TEMPORARY_DIR"
  fi
  echo -e "✅"
}

check_path_exists() {
  local path=$1
  if [ -e "$path" ]; then
    return 0  # Éxito
  else
    return 1  # Error
  fi
}

copy_file() {
  local origin=$1
  local destination=$2
  if check_path_exists "$destination"; then   
    echo -e "${YELLOW}$destination ya existe en el proyecto destino.${NC}" 
	  read -p "¿Deseas actualizar el fichero existente? (s/n): " CONFIRM < /dev/tty

    if [ "$CONFIRM" == "s" ]; then
      echo -e "${BOLD}Actualizando.${NC}..."      
    else
      echo -e "${BOLD}Cancelado.${NC}"   
      return
    fi
  fi
  path_without_folder=$(dirname "$destination")
  echo "Copiando desde ${origin} a ${path_without_folder}"	
  cp -R "${origin}" "${path_without_folder}"
  if [ $? -eq 0 ]; then
    echo -e "✅"
  else
    echo -e "${RED}Error: No se pudo copiar el fichero.${NC}"
  fi 
}	
