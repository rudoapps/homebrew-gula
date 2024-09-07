#!/bin/bash

android_list_modules() {
  local TARGET_DIR=$1
  
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
