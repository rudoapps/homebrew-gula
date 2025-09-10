#!/bin/bash

MAIN_DIRECTORY=""
GULA_LOG_FILE=".gula.log"

# Función para inicializar el archivo de log
init_gula_log() {
  if [ ! -f "$GULA_LOG_FILE" ]; then
    echo '{
  "project_info": {
    "created": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",
    "gula_version": "'$VERSION'"
  },
  "operations": [],
  "installed_modules": {}
}' > "$GULA_LOG_FILE"
  fi
}

# Función para registrar operaciones
log_operation() {
  local operation=$1
  local platform=$2
  local module_name=$3
  local branch=${4:-"main"}
  local status=$5
  local details=${6:-""}
  
  init_gula_log
  
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local log_entry='{
    "timestamp": "'$timestamp'",
    "operation": "'$operation'",
    "platform": "'$platform'",
    "module": "'$module_name'",
    "branch": "'$branch'",
    "status": "'$status'",
    "details": "'$details'",
    "gula_version": "'$VERSION'"
  }'
  
  # Usar jq para añadir la entrada al array de operaciones
  if command -v jq >/dev/null 2>&1; then
    local temp_file=$(mktemp)
    jq ".operations += [$log_entry]" "$GULA_LOG_FILE" > "$temp_file" && mv "$temp_file" "$GULA_LOG_FILE"
  else
    echo "Warning: jq no está disponible, logging simplificado"
    echo "[$timestamp] $operation $platform:$module_name ($branch) - $status" >> ".gula-simple.log"
  fi
}

# Función para registrar módulo instalado exitosamente
log_installed_module() {
  local platform=$1
  local module_name=$2
  local branch=${3:-"main"}
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  init_gula_log
  
  if command -v jq >/dev/null 2>&1; then
    local temp_file=$(mktemp)
    jq ".installed_modules[\"$platform:$module_name\"] = {
      \"platform\": \"$platform\",
      \"module\": \"$module_name\",
      \"branch\": \"$branch\",
      \"installed_at\": \"$timestamp\",
      \"gula_version\": \"$VERSION\"
    }" "$GULA_LOG_FILE" > "$temp_file" && mv "$temp_file" "$GULA_LOG_FILE"
  fi
}

# Función para mostrar el status del proyecto
show_project_status() {
  if [ ! -f "$GULA_LOG_FILE" ]; then
    echo -e "${YELLOW}No se encontró archivo de log. Este proyecto no tiene módulos instalados con gula.${NC}"
    return 1
  fi
  
  if command -v jq >/dev/null 2>&1; then
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}           ESTADO DEL PROYECTO GULA             ${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
    echo ""
    
    # Información del proyecto
    local created=$(jq -r '.project_info.created' "$GULA_LOG_FILE")
    local version=$(jq -r '.project_info.gula_version' "$GULA_LOG_FILE")
    echo -e "${BOLD}Proyecto creado:${NC} $created"
    echo -e "${BOLD}Versión de gula:${NC} $version"
    echo ""
    
    # Módulos instalados
    echo -e "${BOLD}MÓDULOS INSTALADOS:${NC}"
    echo -e "${BOLD}───────────────────────────────────────────────${NC}"
    
    local modules_count=$(jq -r '.installed_modules | length' "$GULA_LOG_FILE")
    if [ "$modules_count" -eq 0 ]; then
      echo "  No hay módulos instalados"
    else
      jq -r '.installed_modules | to_entries[] | "  \(.value.platform) → \(.value.module) (\(.value.branch)) - \(.value.installed_at)"' "$GULA_LOG_FILE"
    fi
    
    echo ""
    echo -e "${BOLD}ÚLTIMAS OPERACIONES:${NC}"
    echo -e "${BOLD}───────────────────────────────────────────────${NC}"
    jq -r '.operations[-5:] | reverse[] | "\(.timestamp) - \(.operation) \(.platform):\(.module) (\(.status))"' "$GULA_LOG_FILE" | head -5
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  else
    echo -e "${RED}Error: jq no está disponible para mostrar el estado del proyecto${NC}"
    if [ -f ".gula-simple.log" ]; then
      echo -e "${YELLOW}Log simplificado disponible:${NC}"
      tail -10 ".gula-simple.log"
    fi
  fi
}

# Función para verificar si un módulo ya está instalado
is_module_installed() {
  local platform=$1
  local module_name=$2
  local key="$platform:$module_name"
  
  if [ ! -f "$GULA_LOG_FILE" ]; then
    return 1  # No instalado (no hay log)
  fi
  
  if command -v jq >/dev/null 2>&1; then
    local installed=$(jq -r ".installed_modules[\"$key\"] // null" "$GULA_LOG_FILE")
    if [ "$installed" != "null" ]; then
      return 0  # Instalado
    fi
  fi
  
  return 1  # No instalado
}

# Función para obtener información del módulo instalado
get_installed_module_info() {
  local platform=$1
  local module_name=$2
  local key="$platform:$module_name"
  
  if command -v jq >/dev/null 2>&1 && [ -f "$GULA_LOG_FILE" ]; then
    jq -r ".installed_modules[\"$key\"] | \"Rama: \(.branch), Instalado: \(.installed_at), Versión gula: \(.gula_version)\"" "$GULA_LOG_FILE"
  fi
}

# Función para manejar reinstalación
handle_module_reinstallation() {
  local platform=$1
  local module_name=$2
  local new_branch=${3:-"main"}
  
  # Si se usa --force, reinstalar automáticamente sin preguntar
  if [ "$FORCE_INSTALL" == "true" ]; then
    echo -e "${YELLOW}⚠️  Módulo ya instalado, reinstalando con --force${NC}"
    log_operation "reinstall" "$platform" "$module_name" "$new_branch" "started" "Reinstalación forzada con --force"
    return 0
  fi
  
  echo ""
  echo -e "${YELLOW}⚠️  MÓDULO YA INSTALADO${NC}"
  echo -e "${BOLD}───────────────────────────────────────────────${NC}"
  echo -e "${BOLD}Módulo:${NC} $module_name"
  echo -e "${BOLD}Plataforma:${NC} $platform"
  
  local info=$(get_installed_module_info "$platform" "$module_name")
  if [ -n "$info" ]; then
    echo -e "${BOLD}Estado actual:${NC} $info"
  fi
  
  echo -e "${BOLD}Nueva rama solicitada:${NC} $new_branch"
  echo ""
  
  echo -e "${BOLD}¿Qué deseas hacer?${NC}"
  echo "  1) Reinstalar (sobrescribir)"
  echo "  2) Cancelar instalación"
  echo ""
  echo -e "${YELLOW}💡 Tip: Usa --force para reinstalar automáticamente sin confirmar${NC}"
  echo ""
  
  while true; do
    read -p "Selecciona una opción (1-2): " choice
    case $choice in
      1)
        echo -e "${GREEN}🔄 Procediendo con la reinstalación...${NC}"
        log_operation "reinstall" "$platform" "$module_name" "$new_branch" "started" "Sobrescribiendo instalación existente"
        return 0  # Continuar con instalación
        ;;
      2)
        echo -e "${YELLOW}❌ Instalación cancelada por el usuario${NC}"
        log_operation "install" "$platform" "$module_name" "$new_branch" "cancelled" "Usuario canceló reinstalación"
        return 1  # Cancelar instalación
        ;;
      *)
        echo -e "${RED}Opción inválida. Por favor selecciona 1 o 2.${NC}"
        ;;
    esac
  done
}

cleanup_temp_directory() {
  if [ -d "$TEMPORARY_DIR" ]; then
    echo -e "${YELLOW}🗑️ Eliminando directorio temporal existente: $TEMPORARY_DIR${NC}"
    rm -rf "$TEMPORARY_DIR"
  fi
  
  # Limpiar cualquier directorio temp-gula si existe en el directorio actual
  if [ -d "temp-gula" ]; then
    echo -e "${YELLOW}🗑️ Eliminando directorio temp-gula existente${NC}"
    rm -rf "temp-gula"
  fi
}

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

list_branches() {
  local repo_type=$1
  local repo_url=""
  
  case "$repo_type" in
    "android")
      repo_url="https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-android.git"
      ;;
    "ios")
      repo_url="https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-ios.git"
      ;;
    "flutter")
      repo_url="https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git"
      ;;
    "python")
      repo_url="https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git"
      ;;
    "archetype-android")
      repo_url="https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-archetype-android.git"
      ;;
    "archetype-ios")
      repo_url="https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-archetype-ios.git"
      ;;
    "archetype-flutter")
      repo_url="https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-archetype-flutter.git"
      ;;
    "archetype-python")
      repo_url="https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-archetype-python.git"
      ;;
    *)
      echo -e "${RED}Error: Tipo de repositorio no válido: $repo_type${NC}"
      echo "Tipos válidos: android, ios, flutter, python, archetype-android, archetype-ios, archetype-flutter, archetype-python"
      exit 1
      ;;
  esac
  
  echo -e "${BOLD}Ramas disponibles para $repo_type:"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  git ls-remote --heads "$repo_url" | sed 's/.*refs\/heads\///' | sort
  echo -e "${BOLD}-----------------------------------------------${NC}"
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
  
  # Validar que el directorio origen existe
  if [ ! -d "$origin" ] && [ ! -f "$origin" ]; then
    echo -e "${RED}❌ Error: El directorio/archivo origen no existe: $origin${NC}"
    echo -e "${YELLOW}📝 Contenido del directorio temporal:${NC}"
    ls -la "$TEMPORARY_DIR" 2>/dev/null || echo "El directorio temporal no existe"
    if [ -d "$TEMPORARY_DIR" ]; then
      echo -e "${YELLOW}📝 Subdirectorios encontrados:${NC}"
      find "$TEMPORARY_DIR" -type d -maxdepth 2 2>/dev/null | head -10
    fi
    log_operation "install" "unknown" "${MODULE_NAME:-unknown}" "${BRANCH:-main}" "error" "Directorio origen no encontrado: $origin"
    remove_temporary_dir
    exit 1
  fi
  
  # Validar que el directorio destino existe o se puede crear
  destination_dir=$(dirname "$destination")
  if [ ! -d "$destination_dir" ]; then
    echo -e "${YELLOW}📁 Creando directorio destino: $destination_dir${NC}"
    mkdir -p "$destination_dir"
  fi
  
  echo -e "${YELLOW}📋 Copiando desde: $origin${NC}"
  echo -e "${YELLOW}📋 Copiando hacia: $destination${NC}"
  
  cp -R "$origin" "$destination"
  if [ $? -eq 0 ]; then
    echo -e "✅ Ficheros copiados exitosamente en: $destination"
  else
    echo -e "${RED}❌ Error: No se pudo copiar desde $origin hacia $destination${NC}"
    echo -e "${YELLOW}📝 Verificando permisos y estructura...${NC}"
    ls -la "$origin" 2>/dev/null || echo "No se puede listar el origen"
    ls -la "$destination_dir" 2>/dev/null || echo "No se puede listar el destino"
    log_operation "install" "unknown" "${MODULE_NAME:-unknown}" "${BRANCH:-main}" "error" "Fallo al copiar: $origin -> $destination"
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

  # Validar que el origen existe
  if [ ! -e "$origin" ]; then
    echo -e "${RED}❌ Error: El archivo/directorio origen no existe: $origin${NC}"
    echo -e "${YELLOW}📝 Verificando directorio temporal:${NC}"
    if [ -d "$TEMPORARY_DIR" ]; then
      echo -e "${YELLOW}Contenido de $TEMPORARY_DIR:${NC}"
      ls -la "$TEMPORARY_DIR" 2>/dev/null | head -10
    fi
    log_operation "install" "unknown" "${MODULE_NAME:-unknown}" "${BRANCH:-main}" "error" "Archivo origen no encontrado: $origin"
    return 1
  fi

  path_without_folder=$(dirname "$destination")
  
  # Crear directorio destino si no existe
  if [ ! -d "$path_without_folder" ]; then
    echo -e "${YELLOW}📁 Creando directorio: $path_without_folder${NC}"
    mkdir -p "$path_without_folder"
  fi
  
  echo -e "${YELLOW}📋 Copiando desde ${origin} a ${path_without_folder}${NC}"	
  cp -R "${origin}" "${path_without_folder}"
  if [ $? -eq 0 ]; then
    echo -e "✅ Copiado desde ${origin} a ${path_without_folder} correctamente"
  else
    echo -e "${RED}❌ Error: No se pudo copiar desde ${origin} a ${path_without_folder}${NC}"
    echo -e "${YELLOW}📝 Información de debugging:${NC}"
    echo -e "  - Origen existe: $([ -e "$origin" ] && echo "✅ Sí" || echo "❌ No")"
    echo -e "  - Destino escribible: $([ -w "$path_without_folder" ] && echo "✅ Sí" || echo "❌ No")"
    ls -la "$origin" 2>/dev/null || echo "  - No se puede listar el origen"
    ls -la "$path_without_folder" 2>/dev/null || echo "  - No se puede listar el destino"
    log_operation "install" "unknown" "${MODULE_NAME:-unknown}" "${BRANCH:-main}" "error" "Fallo al copiar archivo: $origin -> $path_without_folder"
    return 1
  fi 
}	
