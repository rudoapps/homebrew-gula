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

flutter_copy_file_or_create_folder() {
  local origin=$1
  local destination=$2

  if !(check_path_exists "$destination"); then  
    echo "No existe directorio - CREAMOS DIRECTORIO"
    mkdir -p "$destination"
  fi

  if [ -d "$origin" ]; then
    echo "📁 Copiando directorio $origin → $destination"
    cp -R "${origin}/." "$destination"
  elif [ -f "$origin" ]; then
    echo "📄 Copiando archivo $origin → $destination"
    cp "$origin" "$destination"
  else
    echo "❌ Error: $origin no existe"
    return 1
  fi

  if [ $? -eq 0 ]; then
    echo -e "✅ Copiado a ${destination} correctamente"
  else
    echo -e "${RED}Error: No se pudo copiar el fichero.${NC}"
    return 1
  fi

  delete_this="/lib"
  destination_without_lib="${destination/$delete_this/}"
  flutter_read_versions_and_install_pubspec "${destination_without_lib}/"
}

flutter_read_configuration() {
  local path="$1"
  configuration="${TEMPORARY_DIR}/lib/${path}configuration.gula"

  echo "Verificando y copiando archivos compartidos..."
  echo ""
  flutter_read_versions_and_install_pubspec "/lib/${path}"
  jq -r '.shared? // [] | .[]' "$configuration" | while read -r file; do
    origin=${TEMPORARY_DIR}/lib/${file}
    destination="lib/${file}"
    flutter_copy_file_or_create_folder "$origin" "$destination"
  done
}

flutter_read_versions_and_install_pubspec() {
  local path="$1"
  json_file="${TEMPORARY_DIR}/${path}configuration.gula"
  pubspec="pubspec.yaml"

  added_libraries=()
  added_dev_libraries=()
  libraries_to_add=""
  dev_libraries_to_add=""

  # Líneas de anclaje
  start_dependencies_line=$(grep -n '^dependencies:$' "$pubspec" | cut -d: -f1)
  start_dev_dependencies_line=$(grep -n '^dev_dependencies:$' "$pubspec" | cut -d: -f1)

  if !(check_path_exists "$json_file"); then
    echo -e "${YELLOW}🟡 No existe configuración para este módulo.${NC}\n"
    return
  fi

  if [[ -z "$start_dependencies_line" ]]; then
    echo "No se encontró la sección [dependencies] en el archivo pubspec"
    return
  fi

  # Si no existe la sección dev_dependencies, la creamos al final (vacía)
  if [[ -z "$start_dev_dependencies_line" ]]; then
    echo "dev_dependencies:" >> "$pubspec"
    start_dev_dependencies_line=$(grep -n '^dev_dependencies:$' "$pubspec" | cut -d: -f1)
  fi

  echo -e "${GREEN}✅ Configuración encontrada.${NC}"
  echo "   | Instalando dependencias desde [ ${json_file} ]"
  echo "   |"

  # ---- DEPENDENCIES ----
  while read -r entry; do
    name=$(echo "$entry" | jq -r '.name')
    version=$(echo "$entry" | jq -r '.version // empty')
    git_url=$(echo "$entry" | jq -r '.git.url // empty')
    # compat: usa .git.ref si existe; si no, .git.version (legacy); si no, vacío
    git_ref=$(echo "$entry" | jq -r '.git.ref // .git.version // empty')

    if grep -qE "^[[:space:]]*$name:" "$pubspec"; then
      echo "   | ✅ $name ya está en el pubspec.yaml"
    else
      if [[ -n "$git_url" ]]; then
        echo "   | ➕ $name (git) → [dependencies]"
        libraries_to_add+="  $name:\n    git:\n      url: \"$git_url\"\n"
        if [[ -n "$git_ref" ]]; then
          libraries_to_add+="      ref: \"$git_ref\"\n"
        fi
      elif [[ -n "$version" ]]; then
        echo "   | ➕ $name → [dependencies]"
        libraries_to_add+="  $name: \"$version\"\n"
      else
        echo "   | ❌ No se encontró ni versión ni git para $name"
        continue
      fi
      added_libraries+=("$name")
    fi
  done < <(jq -c '.libraries? // [] | .[]' "$json_file")

  # ---- DEV_DEPENDENCIES ----
  echo "   |"
  echo "   | Instalando dev dependencias (dev_libraries)"
  while read -r entry; do
    name=$(echo "$entry" | jq -r '.name')
    version=$(echo "$entry" | jq -r '.version // empty')
    git_url=$(echo "$entry" | jq -r '.git.url // empty')
    git_ref=$(echo "$entry" | jq -r '.git.ref // .git.version // empty')

    # comprobamos si ya existe en cualquier sección
    if grep -qE "^[[:space:]]*$name:" "$pubspec"; then
      echo "   | ✅ $name ya está en el pubspec.yaml"
    else
      if [[ -n "$git_url" ]]; then
        echo "   | ➕ $name (git) → [dev_dependencies]"
        dev_libraries_to_add+="  $name:\n    git:\n      url: \"$git_url\"\n"
        if [[ -n "$git_ref" ]]; then
          dev_libraries_to_add+="      ref: \"$git_ref\"\n"
        fi
      elif [[ -n "$version" ]]; then
        echo "   | ➕ $name → [dev_dependencies]"
        dev_libraries_to_add+="  $name: \"$version\"\n"
      else
        echo "   | ❌ No se encontró ni versión ni git para $name (dev)"
        continue
      fi
      added_dev_libraries+=("$name")
    fi
  done < <(jq -c '.dev_libraries? // [] | .[]' "$json_file")

  # ---- APLICAR CAMBIOS ----
  libraries_to_add=$(printf "%b" "$libraries_to_add")
  dev_libraries_to_add=$(printf "%b" "$dev_libraries_to_add")

  if [[ ${#added_libraries[@]} -gt 0 ]]; then
    echo "   |"
    echo "   | ✅ Añadiendo a [dependencies]…"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      printf '%s\n' "$libraries_to_add" | sed -i '' "/^dependencies:/r /dev/stdin" "$pubspec"
    else
      printf '%s\n' "$libraries_to_add" | sed -i "/^dependencies:/r /dev/stdin" "$pubspec"
    fi
  else
    echo "   |"
    echo "   | ℹ️ No hay nuevas librerías para [dependencies]"
  fi

  if [[ ${#added_dev_libraries[@]} -gt 0 ]]; then
    echo "   |"
    echo "   | ✅ Añadiendo a [dev_dependencies]…"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      printf '%s\n' "$dev_libraries_to_add" | sed -i '' "/^dev_dependencies:/r /dev/stdin" "$pubspec"
    else
      printf '%s\n' "$dev_libraries_to_add" | sed -i "/^dev_dependencies:/r /dev/stdin" "$pubspec"
    fi
  else
    echo "   |"
    echo "   | ℹ️ No hay nuevas librerías para [dev_dependencies]"
  fi

  echo "   └──────────────────────────────────────────"
}

