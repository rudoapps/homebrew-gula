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

  echo $destination
  if !(check_path_exists "$destination"); then  
    echo "No existe CREAMOS DIRECTORIO"
    mkdir -p "$destination"
  fi

  cp -R "${origin}/." "${destination}"
  if [ $? -eq 0 ]; then
    echo -e "✅ Copiado desde ${origin} a ${destination} correctamente"
  else
    echo -e "${RED}Error: No se pudo copiar el fichero.${NC}"
  fi
  android_install_libraries_dependencies "${origin}/configuration.gula"
  android_install_gradle_dependencies "${origin}/configuration.gula"
} 

flutter_read_configuration() {
  local path="$1"
  FILE="${TEMPORARY_DIR}/lib/${path}configuration.gula"

  echo "Verificando y copiando archivos compartidos..."
  jq -r '.shared[]' "$FILE" | while read -r file; do
      origin=${TEMPORARY_DIR}/lib/${file}
      destination="lib/${file}"
      flutter_copy_file_or_create_folder $origin $destination
  done

  echo "Verificando y agregando dependencias a pubspec.yaml..."
  jq -r '.libraries[] | "\(.name): \(.version)"' "$FILE" | while read -r dependency; do
      NAME=$(echo "$dependency" | cut -d':' -f1)
      VERSION=$(echo "$dependency" | cut -d':' -f2 | xargs)

      if echo "$library" | jq -e 'has("git")' > /dev/null; then
          # Dependencia de Git
          GIT_URL=$(echo "$library" | jq -r '.git.url')
          GIT_VERSION=$(echo "$library" | jq -r '.git.version')

          # Verificar si la librería ya está en el pubspec.yaml
          if grep -q "$NAME:" "pubspec.yaml"; then
              echo "La librería $NAME ya está en el pubspec.yaml. No se agregará."
          else
              echo "Agregando $NAME desde Git ($GIT_URL) con versión $GIT_VERSION al pubspec.yaml"
              sed -i '' "/dependencies:/a\\
    $NAME:\\
      git:\\
        url: $GIT_URL\\
        ref: $GIT_VERSION\\
  " pubspec.yaml
          fi
      else
        if grep -q "$NAME:" "pubspec.yaml"; then
            echo "La librería $NAME ya está en el pubspec.yaml. No se agregará."
        else
            echo "Agregando $NAME con versión $VERSION al pubspec.yaml"
            sed -i '' "/dependencies:/a\\
    $dependency\\
  " pubspec.yaml
        fi
      fi
  done

  # Ejecutar flutter pub get para actualizar dependencias
  

  echo "¡Proceso completado!"

}

flutter_read_versions_and_install_pubspec() {
  local path="$1"
  json_file="${TEMPORARY_DIR}/lib/${path}configuration.gula"
  pubspec="pubspec.yaml"

  added_libraries=()
  libraries_to_add=""
  start_versions_line=$(grep -n '^dependencies:$' "$pubspec" | cut -d: -f1)

  if [[ -z "$start_versions_line" ]]; then
    echo "No se encontró la sección [dependencies] en el archivo pubspec"
    return
  fi

  echo "-----------------------------------------------"
  echo "[DEPENDENCIES] Buscando dependencias"
  echo "Configuración: ${json_file}"
  echo "Pubspec: ${pubspec}"
  echo "-----------------------------------------------"

  while read -r entry; do
    name=$(echo "$entry" | jq -r '.name')
    version=$(echo "$entry" | jq -r '.version // empty')  # Version puede ser opcional
    git_url=$(echo "$entry" | jq -r '.git.url // empty')  # Propiedad opcional de git
    git_version=$(echo "$entry" | jq -r '.git.version // empty')  # Propiedad opcional de git

    if grep -q "$name:" "$pubspec"; then
      echo "✅ $name ya está en el pubspec.yaml"
    else
      if [[ -n "$git_url" ]]; then
        # Si existe la propiedad git, añadirlo con su URL y versión (si existe)
        echo "➕ $name (git) no está en el pubspec. Añadiendo a la lista para [dependencies]..."
        libraries_to_add+="  $name:\n    git:\n      url: \"$git_url\"\n"
        if [[ -n "$git_version" ]]; then
          libraries_to_add+="      version: \"$git_version\"\n"
        fi
      elif [[ -n "$version" ]]; then
        # Si existe la versión, añadirlo como dependencia normal
        echo "➕ $name no está en el pubspec. Añadiendo a la lista para [dependencies]..."
        libraries_to_add+="  $name: \"$version\"\n"
      else
        echo "❌ No se encontró ni versión ni git para $name"
      fi
      added_libraries+=("$name")  # Añadir al array de añadidos
    fi
  done < <(jq -c '.libraries[]' "$json_file")

  if [[ ${#added_libraries[@]} -gt 0 ]]; then
    echo "Librerías añadidas al archivo pubspec en la sección [dependencies]:"

    libraries_to_add=$(printf "%b" "$libraries_to_add")

    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      printf '%s\n' "$libraries_to_add" | sed -i '' "/^dependencies:/r /dev/stdin" "$pubspec"
    else
      printf '%s\n' "$libraries_to_add" | sed -i "/^dependencies:/r /dev/stdin" "$pubspec"
    fi
    echo "✅ Dependencias añadidas correctamente."
  else
    echo "No se han añadido nuevas dependencias."
  fi

  echo "Ejecutando flutter pub get..."
  flutter pub get
  echo ""
}

