#!/bin/bash

android_list_modules() {  
  EXCLUDE_DIRS=("app" "gradle" "shared")
  for dir in "$TARGET_DIR"/*/; do
    # Extraer solo el nombre del directorio
    dir_name=$(basename "$dir")

    # Variable para determinar si el directorio está en la lista de exclusión
    exclude=0

    # Verificar si el directorio está en la lista de exclusión
    for exclude_dir in "${EXCLUDE_DIRS[@]}"; do
      if [[ "$dir_name" == "$exclude_dir" ]]; then
        exclude=1
        break
      fi
    done

    # Si no está en la lista de exclusión, imprimir el directorio
    if [[ $exclude -eq 0 ]]; then
      echo "$dir_name"
    fi
  done
}

android_check_module_in_temporary_dir() {
  local module=$1
  if [ ! -d "$TEMPORARY_DIR/${module}" ]; then
    echo -e "${RED}Error: El módulo $module no existe en el repositorio.${NC}"
    echo -e "${RED}No encontrado en: $TEMPORARY_DIR"
    rm -rf "$TEMPORARY_DIR"
    exit 1
  fi
  echo -e "✅ Módulo existe correctamente"
}

android_detect_package_name() {
  if [ -d "$ANDROID_PROJECT_SRC" ]; then
    # Encontrar el primer directorio que contenga un archivo .java o .kt
    MAIN_DIRECTORY=$(find "$ANDROID_PROJECT_SRC" -type f \( -name "*.java" -o -name "*.kt" \) -print0 | xargs -0 -n1 dirname | sort -u | head -n 1)
    
    if [ -n "$MAIN_DIRECTORY" ]; then
      echo -e "${GREEN}✅ Encontrado package: $MAIN_DIRECTORY${NC}"
    else
      echo -e "${RED}No se encontraron archivos .java o .kt en $ANDROID_PROJECT_SRC${NC}"
    fi
  else
    echo -e "${RED}No se encontró la ruta base en: $ANDROID_PROJECT_SRC${NC}"
  fi
}


android_verify_module() {
  local module=$1
  MODULE_PATH="$module"
  if [ -d "$MODULE_PATH" ]; then
    echo -e "${YELLOW}El módulo $module ya existe en el proyecto destino.${NC}"
    read -p "¿Deseas actualizar el módulo existente? (s/n): " CONFIRM
    if [ "$CONFIRM" != "s" ]; then
      echo "  Instalación del módulo cancelada."
      exit 0
    fi
    rm -rf "$MODULE_PATH"
    echo -e "✅ Actualización en curso"
  else 
    echo -e "✅ Módulo no detectado continua la instalación"
  fi
}

android_create_modules_dir() {
  EXISTS_THIS_DIR=${MODULE_NAME}
  if [ ! -d "$EXISTS_THIS_DIR" ]; then
    echo -e "${YELLOW}La carpeta '${MODULE_NAME}' no existe. Creándola...${NC}"
    mkdir -p "$EXISTS_THIS_DIR"
    if [ $? -eq 0 ]; then
      echo -e "✅ Módulo '${MODULE_NAME}' creado correctamente"
    else
      echo -e "${RED}Error: No se pudo crear la carpeta '${MODULE_NAME}'.${NC}"
      exit 1
    fi 
  fi
}

android_rename_imports() {
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
    echo -e "✅ Renombrado completado"
  else
    echo -e "${RED}Error: No se ha podido renombrar.${NC}"
    remove_temporary_dir
    exit 1
  fi
}

android_read_configuration_temporal() {
  FILE="$TEMPORARY_DIR/${MODULE_NAME}/configuration.gula"
  if [ ! -f "$FILE" ]; then
    echo -e "${RED}Error: El fichero $FILE no existe.${NC}"
  else
    echo "Extrayendo dependencias de: $TEMPORARY_DIR/${MODULE_NAME}/configuration.gula"
    while IFS= read -r line; do   
      if check_directory_exists "./$line"; then    
        copy_file "${TEMPORARY_DIR}/$line" "."
        if [ $? -eq 0 ]; then
          echo -e "✅ $line copiado correctamente"
        else
          echo -e "${RED}Error: No se ha podido renombrar.${NC}"
          remove_temporary_dir
          exit 1
        fi
      fi
    done < "$FILE"
  fi
}

android_read_configuration() {
  # Verificar si el fichero existe
  FILE="$TEMPORARY_DIR/${MODULE_NAME}/configuration.gula"
  if [ ! -f "$FILE" ]; then
    echo -e "${RED}Error: El fichero $FILE no existe.${NC}"
  else
    # Leer el fichero línea por línea
    while IFS= read -r line; do
      # Extraer el tipo (assets, strings, colors, dimens)
      type=$(echo "$line" | cut -d'/' -f1)
      
      # Extraer la parte de la ruta a transformar
      path=$(echo "$line" | cut -d'/' -f2-)
      
      if [ "$type" == "libraries" ]; then
        android_install_library $path
      elif [[ "$type" == "drawables" || "$type" == "strings" ]]; then
        extension="${path##*.}"
        # Eliminar la extensión del archivo para procesar el resto de la ruta
        path_without_extension="${path%.*}"
        # Reemplazar los puntos por barras en la parte de la ruta
        transformed_path=$(echo "$path_without_extension" | sed 's/\./\//g')
        # Volver a agregar la extensión al final
        final_path="$transformed_path.$extension"
        android_decide_what_to_do_with_file $type $final_path
      else
        # Reemplazar los puntos por barras
        transformed_path=$(echo "$path" | sed 's/\./\//g')
        # Mostrar el tipo y la ruta transformada
        android_decide_what_to_do_with_file $type $transformed_path
      fi
      
    done < "$FILE"
  fi
}


android_decide_what_to_do_with_file() {
  local type=$1
  local path=$2
  
  if [ "$type" == "components" ]; then
    component=$(basename "$2")    
      copy_file "${TEMPORARY_DIR}/${ANDROID_PROJECT_SRC}/${path}" "${MAIN_DIRECTORY}/shared/components/${component}"
  elif [[ "$type" == "drawables" || "$type" == "strings" ]]; then 
      copy_file "${TEMPORARY_DIR}/app/src/main/${path}" "app/src/main/${path}"
  else
    echo "Copying file of ${type}: ${path} to ${ANDROID_PROJECT_RES}/${path}"
    echo -e "${YELLOW}Este fichero no se va a copiar debe de revisarse antes${NC}"
  fi
}

android_install_library() {
  local type=$1
  echo "Instalando librería: ${path}"
  echo -e "${YELLOW}Esta librería no se va a instalar todavía.${NC}"

  BUILD_GRADLE_PATH="app/build.gradle.kts"  # Cambia esta ruta según el módulo

  # Verificar si el archivo build.gradle existe
  if [ ! -f "$BUILD_GRADLE_PATH" ]; then
    echo "Error: No se encontró el archivo $BUILD_GRADLE_PATH."
    exit 1
  fi

  # android_add_library_if_missing ${path}
}

android_add_library_if_missing() {
  local library=$1
  if grep -q "$library" "$BUILD_GRADLE_PATH"; then
    echo "La librería '$library' ya está en $BUILD_GRADLE_PATH."
  else
    echo "Añadiendo '$library' a $BUILD_GRADLE_PATH."
    # Añadir la librería dentro del bloque dependencies {
    sed -i.bak "/dependencies {/a\    implementation  $library" "$BUILD_GRADLE_PATH"
  fi
}

transform_string() {
  local input_string="$1"
  # Remover el guion y capitalizar la parte después del guion
  transformed_string=$(echo "$input_string" | sed -E 's/-([a-z])/\U\1/g')
  echo "$transformed_string"
}

android_install_libraries_dependencies() {
  json_file="$TEMPORARY_DIR/${MODULE_NAME}/configuration.gula"
  # Archivo TOML donde verificar las versiones
  toml_file="gradle/libs.versions.toml"

    if [[ ! -f "$json_file" ]]; then
    echo "El archivo JSON no existe: $json_file"
    exit 1
  fi

  # Comprobar si el archivo TOML existe
  if [[ ! -f "$toml_file" ]]; then
    echo "El archivo TOML no existe: $toml_file"
    exit 1
  fi

  # Variables para llevar el control de las librerías añadidas
  added_libraries=()
  libraries_to_add=""

  # Identificar la línea donde comienza la sección [versions]
  start_versions_line=$(grep -n '^\[versions\]$' "$toml_file" | cut -d: -f1)

  # Si no se encuentra la sección [versions], salir con un error
  if [[ -z "$start_versions_line" ]]; then
    echo "No se encontró la sección [versions] en el archivo TOML"
    exit 1
  fi

  # Identificar la línea donde comienza la sección [libraries]
  start_libraries_line=$(grep -n '^\[libraries\]$' "$toml_file" | cut -d: -f1)

  # Si no se encuentra la sección [libraries], salir con un error
  if [[ -z "$start_libraries_line" ]]; then
    echo "No se encontró la sección [libraries] en el archivo TOML"
    exit 1
  fi

  echo "-----------------------------------------------"
  echo " Buscando dependencias para [versions]"
  echo "-----------------------------------------------"
  # Recorrer las versiones en el bloque 'toml' del JSON
  while read -r entry; do
    # Extraer las propiedades name, version, group y module
    name=$(echo "$entry" | jq -r '.name')
    version=$(echo "$entry" | jq -r '.version')
    group=$(echo "$entry" | jq -r '.group // empty')
    module=$(echo "$entry" | jq -r '.module // empty')

    # Comprobar si la versión ya existe en el bloque [versions]
    if grep -q "^$name" "$toml_file"; then
      echo "✔ $name ya está en la versión $version en el TOML"
    else
      echo "✘ $name no está en el TOML. Añadiendo a la lista para [versions]..."
      libraries_to_add+="$name = \"$version\"\n"
      added_libraries+=("$name")  # Añadir al array de añadidos
    fi
  done < <(jq -c '.toml[]' "$json_file")

  # Si hay librerías para añadir a [versions], las insertamos de golpe después de [versions]
  if [[ ${#added_libraries[@]} -gt 0 ]]; then
    echo "Librerías añadidas al archivo TOML en la sección [versions]:"

    # Usar printf para asegurar que los saltos de línea se manejen correctamente
    libraries_to_add=$(printf "%b" "$libraries_to_add")

    # Insertar todas las librerías de una vez justo después de [versions]
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      printf '%s\n' "$libraries_to_add" | sed -i '' "/^\[versions\]/r /dev/stdin" "$toml_file"
    else
      # Linux
      printf '%s\n' "$libraries_to_add" | sed -i "/^\[versions\]/r /dev/stdin" "$toml_file"
    fi
  else
    echo "No se han añadido nuevas librerías a [versions]."
  fi

  # Ahora vamos a manejar la sección [libraries]
  libraries_to_add=""
  echo "-----------------------------------------------"
  echo " Buscando dependencias para [libraries]"
  echo "-----------------------------------------------"
  while read -r entry; do
    name=$(echo "$entry" | jq -r '.name')
    group=$(echo "$entry" | jq -r '.group // empty')
    module=$(echo "$entry" | jq -r '.module // empty')

    # Construir el formato correcto según si es group o module
    if [[ -n "$group" ]]; then
      new_library="$name = { group = \"$group\", name = \"$name\", version.ref = \"$(transform_string $name)\" }"
    elif [[ -n "$module" ]]; then
      new_library="$name = { module = \"$module\", name = \"$name\", version.ref = \"$(transform_string $name)\"  }"
    else
      continue  # Si no hay ni group ni module, saltar
    fi

    # Comprobar si la librería ya está en [libraries]
    if grep -q "= \"$group\"" "$toml_file"; then
      echo "✔ $name ya está en [libraries] del TOML"
    elif grep -q "= \"$module\"" "$toml_file"; then      
      echo "✔ $name ya está en [libraries] del TOML"
    else
      echo "✘ $name no está en [libraries]. Añadiendo a la lista para [libraries]..."
      libraries_to_add+="$new_library\n"
    fi

  done < <(jq -c '.toml[]' "$json_file")
 
  # Si hay librerías para añadir a [libraries], las insertamos de golpe después de [libraries]
  if [[ -n "$libraries_to_add" ]]; then
    # Usar printf para asegurar que los saltos de línea se manejen correctamente
    libraries_to_add=$(printf "%b" "$libraries_to_add")

    # Insertar todas las librerías de una vez justo después de [libraries]
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      printf '%s\n' "$libraries_to_add" | sed -i '' "/^\[libraries\]/r /dev/stdin" "$toml_file"
    else
      # Linux
      printf '%s\n' "$libraries_to_add" | sed -i "/^\[libraries\]/r /dev/stdin" "$toml_file"
    fi
    echo "Añadiendo dependencias"
  else
    echo "No se han añadido nuevas librerías a [libraries]."
  fi

  plugins_to_add=""
  echo "-----------------------------------------------"
  echo " Buscando dependencias para [plugins]"
  echo "-----------------------------------------------"
  while read -r entry; do
    name=$(echo "$entry" | jq -r '.name')
    plugin=$(echo "$entry" | jq -r '.plugin // empty')
    id=$(echo "$entry" | jq -r '.id // empty')

    if [[ -n "$plugin" ]]; then
      new_plugin="$id = { id = \"$plugin\", version.ref = \"$(transform_string $name)\" }"
    else
      continue
    fi

    if grep -q "^$id = " "$toml_file"; then
      echo "✔ $id ya está en [plugins] del TOML"
    else
      plugins_to_add+="$new_plugin\n"
    fi
  done < <(jq -c '.toml[]' "$json_file")

  if [[ -n "$plugins_to_add" ]]; then
    # Usar printf para asegurar que los saltos de línea se manejen correctamente
    plugins_to_add=$(printf "%b" "$plugins_to_add")

    # Insertar todas las librerías de una vez justo después de [libraries]
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      printf '%s\n' "$plugins_to_add" | sed -i '' "/^\[plugins\]/r /dev/stdin" "$toml_file"
    else
      # Linux
      printf '%s\n' "$plugins_to_add" | sed -i "/^\[plugins\]/r /dev/stdin" "$toml_file"
    fi
    echo "Añadiendo dependencias"
  else
    echo "No se han añadido nuevas librerías a [plugins]."
  fi
}

android_install_gradle_dependencies() {
  echo "-----------------------------------------------"
  echo " Buscando dependencias para gradle"
  echo "-----------------------------------------------"
  # JSON file
  json_file="$TEMPORARY_DIR/${MODULE_NAME}/configuration.gula"
  # settings.gradle.kts file
  gradle_file="settings.gradle.kts"

if [[ ! -f "$json_file" ]]; then
  echo "El archivo JSON no existe: $json_file"
  exit 1
fi

# Comprobar si el archivo de Gradle existe
if [[ ! -f "$gradle_file" ]]; then
  echo "El archivo Gradle no existe: $gradle_file"
  exit 1
fi

# Leer las propiedades `includes` y `dependencies` del JSON
includes=$(jq -r '.gradle.includes[]' "$json_file")
dependencies=$(jq -c '.gradle.dependencies[]' "$json_file")

# Variable para acumular los includes
includes_to_add=""

# Acumular los `include` en la variable
echo "Acumulando includes..."

for include in $includes; do
  # Comprobar si la línea ya existe en el archivo
  if grep -q "include(\"$include\")" "$gradle_file"; then
    echo "✔ $include ya está en el archivo"
  else
    echo "✘ $include no está en el archivo. Acumulándolo..."
    includes_to_add+="\ninclude(\"$include\")"
  fi
done

# Si hay includes para añadir, los insertamos de golpe
if [[ -n "$includes_to_add" ]]; then
  echo "Añadiendo includes acumulados al archivo..."
  
  # Usar printf para manejar el salto de línea correctamente
  includes_to_add=$(printf "%b" "$includes_to_add")

  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    printf '%s\n' "$includes_to_add" | sed -i '' "/^include(\"/r /dev/stdin" "$gradle_file"
  else
    # Linux
    printf '%s\n' "$includes_to_add" | sed -i "/^include(\"/r /dev/stdin" "$gradle_file"
  fi
else
  echo "No hay includes nuevos que añadir."
fi

# Variable para acumular los repositories
repositories_to_add=""

# Añadir los `repositories` en la sección correcta del archivo settings.gradle.kts
echo "Acumulando dependencias de repositories..."

for dep in $dependencies; do
  name=$(echo "$dep" | jq -r '.name')
  url=$(echo "$dep" | jq -r '.url')

  # Comprobar si el repositorio ya existe en el archivo
  if grep -q "maven(\"$url\")" "$gradle_file"; then
    echo "✔ $url ya está en el archivo"
  else
    echo "✘ $url no está en el archivo. Acumulándolo..."
    repositories_to_add+="maven(\"$url\")\n"
  fi
done

# Si hay repositories para añadir, los insertamos en el bloque correcto
if [[ -n "$repositories_to_add" ]]; then
  echo "Añadiendo repositories acumulados al archivo..."
  
  # Usar printf para manejar el salto de línea correctamente
  repositories_to_add=$(printf "%b" "$repositories_to_add")

  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    printf '%s\n' "$repositories_to_add" | sed -i '' "/repositories {/r /dev/stdin" "$gradle_file"
  else
    # Linux
    printf '%s\n' "$repositories_to_add" | sed -i "/repositories {/r /dev/stdin" "$gradle_file"
  fi
else
  echo "No hay nuevos repositories que añadir."
fi

echo "✅ Modificaciones completadas."
}