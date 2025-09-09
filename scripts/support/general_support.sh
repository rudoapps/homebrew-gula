#!/bin/bash

MAIN_DIRECTORY=""

standardized_list_modules() {
  local modules_path=$1
  shift
  local exclude_dirs=("$@")  # Directorios a excluir (opcional)
  
  # Construir la ruta completa
  local search_path="$TEMPORARY_DIR"
  if [ -n "$modules_path" ]; then
    search_path="$TEMPORARY_DIR/$modules_path"
  fi
  
  for dir in "$search_path"/*/; do
    [ ! -d "$dir" ] && continue
    
    dir_name=$(basename "$dir")
    
    # Verificar si debe excluirse
    local exclude=0
    if [ ${#exclude_dirs[@]} -gt 0 ]; then
      for exclude_dir in "${exclude_dirs[@]}"; do
        if [[ "$dir_name" == "$exclude_dir" ]]; then
          exclude=1
          break
        fi
      done
    fi
    
    if [[ $exclude -eq 0 ]]; then
      echo "$dir_name"
    fi
  done
}

check_type_of_project() {
  # Android: settings.gradle + directorio app
  if ([ -f "settings.gradle" ] || [ -f "settings.gradle.kts" ]) && [ -d "app" ]; then
      return 0  # Proyecto Android
  elif find . -maxdepth 1 -name "*.xcodeproj" | grep -q .; then
      return 1  # Proyecto iOS (Xcode)
  elif [ -f "pubspec.yaml" ]; then
      return 2  # Proyecto Flutter (Dart)
  elif [ -f "requirements.txt" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
      return 3  # Proyecto Python
  else
      return 4  # Tipo de proyecto desconocido
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
  
  # Limpiar directorio temp-gula si existe
  if [ -d "temp-gula" ]; then
    echo -e "🗑️ Eliminando directorio temp-gula..."
    rm -rf "temp-gula"
    echo -e "✅ Directorio temp-gula eliminado"
  fi
  
  echo ""
  echo -e "✅ Limpieza de directorios temporales completada"
  echo ""
  echo -e "Fin de la ejecución"
  echo ""
  exit 1
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
  cp -R "${origin}" "${path_without_folder}"
  if [ $? -eq 0 ]; then
    echo -e "✅ Copiado desde ${origin} a ${path_without_folder} correctamente"
  else
    echo -e "${RED}Error: No se pudo copiar el fichero.${NC}"
  fi 
}	
