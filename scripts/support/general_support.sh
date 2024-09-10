#!/bin/bash

MAIN_DIRECTORY=""

check_type_of_project() {
  if [ -d "$ANDROID_PROJECT_SRC" ]; then
      return 0  # Proyecto Android
  elif find . -maxdepth 1 -name "*.xcodeproj" | grep -q .; then
      return 1  # Proyecto iOS (Xcode)
  elif [ -f "pubspec.yaml" ]; then
      return 2  # Proyecto Flutter (Dart)
  elif [ -f "requirements.txt" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
      return 3  # Proyecto Python
  else
      return -1  # Tipo de proyecto desconocido
  fi
}
copy_files() {
  local origin=$1
  local destination=$2
  
  cp -R $1 $2
  if [ $? -eq 0 ]; then
    echo -e "✅ Ficheros copiados en: $2"
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
  echo -e "✅ Directorio temporal eliminado"
}

check_path_exists() {
  local path=$1
  if [ -e "$path" ]; then
    return 0  # Éxito
  else
    return 1  # Error
  fi
}

check_directory_exists() {
  local destination=$1
  if check_path_exists "$destination"; then   
    echo -e "${YELLOW}$destination ya existe en el proyecto destino.${NC}" 
    read -p "¿Deseas actualizar el fichero existente? (s/n): " CONFIRM < /dev/tty

    if [ "$CONFIRM" == "s" ]; then
      echo -e "${BOLD}Actualizando.${NC}..."
      return 0     
    else
      echo -e "${BOLD}Cancelado.${NC}"   
      return 1
    fi
  fi
}

copy_file() {
  local origin=$1
  local destination=$2

  path_without_folder=$(dirname "$destination")
  echo "Copiando desde ${origin} a ${path_without_folder}"	
  cp -R "${origin}" "${destination}"
  if [ $? -eq 0 ]; then
    echo -e "✅ Copiado desde ${origin} a ${path_without_folder} correctamente"
  else
    echo -e "${RED}Error: No se pudo copiar el fichero.${NC}"
  fi 
}	
