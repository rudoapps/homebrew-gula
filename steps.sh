#!/bin/bash

MAIN_DIRECTORY=""

# Ruta del módulo en el proyecto destino
check_is_android() {
  if [ ! -d "$ANDROID_PROJECT_SRC" ]; then
    echo -e "${RED}Error: No te encuentras en un proyecto Android.${NC}"
    exit 0
  fi
}

detect_package_name() {
  if [ -d "$ANDROID_PROJECT_SRC" ]; then
    # Encontrar el primer directorio que contenga un archivo .java o .kt
    MAIN_DIRECTORY=$(find "$ANDROID_PROJECT_SRC" -type f \( -name "*.java" -o -name "*.kt" \) -print0 | xargs -0 -n1 dirname | sort -u | head -n 1)
    
    if [ -n "$MAIN_DIRECTORY" ]; then
      echo -e "${GREEN}OK. Encontrado package: $MAIN_DIRECTORY${NC}"
    else
      echo -e "${RED}No se encontraron archivos .java o .kt en $ANDROID_PROJECT_SRC${NC}"
    fi
  else
    echo -e "${RED}No se encontró la ruta base en: $ANDROID_PROJECT_SRC${NC}"
  fi
}

clone() {
  remove_temporary_dir
  # Clonar el repositorio específico desde Bitbucket en un directorio temporal
  local repository=$1
  git clone "$repository" --branch main --single-branch --depth 1 "${TEMPORARY_DIR}"
  if [ $? -eq 0 ]; then
      echo -e "${GREEN}OK.${NC}"
  else
    echo -e "${RED}Se ha producido un error descargando el repositorio.${NC}"
    exit 1
  fi 
}

check_module_in_temporary_dir() {
  if [ ! -d "$TEMPORARY_DIR/${MODULES_PATH}${MODULE_NAME}" ]; then
    echo -e "${RED}Error: El módulo $MODULE_NAME no existe en el repositorio.${NC}"
    echo -e "${RED}No encontrado en: $MODULES_PATH"
    rm -rf "$TEMPORARY_DIR"
    exit 1
  fi
  echo -e "${GREEN}OK.${NC}"
}

verify_module() {
  MODULE_PATH="${MAIN_DIRECTORY}/modules/$MODULE_NAME"
  if [ -d "$MODULE_PATH" ]; then
    echo -e "${YELLOW}El módulo $MODULE_NAME ya existe en el proyecto destino.${NC}"
    read -p "¿Deseas actualizar el módulo existente? (s/n): " CONFIRM
    if [ "$CONFIRM" != "s" ]; then
      echo "  Instalación del módulo cancelada."
      exit 0
    fi
    rm -rf "$MODULE_PATH"
    echo -e "${GREEN}OK.${NC}"
  else 
    echo -e "${GREEN}OK.${NC}"
  fi
}

create_modules_dir() {
  EXISTS_THIS_DIR=${MAIN_DIRECTORY}/modules/${MODULE_NAME}
  if [ ! -d "$EXISTS_THIS_DIR" ]; then
    echo -e "${YELLOW}La carpeta '${MODULE_NAME}' no existe. Creándola...${NC}"
    mkdir -p "$EXISTS_THIS_DIR"
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}OK.${NC}"
    else
      echo -e "${RED}Error: No se pudo crear la carpeta '${MODULE_NAME}'.${NC}"
      exit 1
    fi 
  fi
}

copy_files() {
  echo -e "${YELLOW}Inicio copiado de del módulo ${MODULE_NAME} en: ${MAIN_DIRECTORY}/modules/${MODULE_NAME}${NC}"
  cp -R "${TEMPORARY_DIR}/${MODULES_PATH}${MODULE_NAME}" "${MAIN_DIRECTORY}/modules/"
  # Validar si el comando se ejecutó correctamente
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}OK.${NC}"
  else
    echo -e "${RED}Error: No se ha podido copiar el módulo.${NC}"
    remove_temporary_dir
    exit 1
  fi
}

rename_imports() {
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
    echo -e "${GREEN}OK.${NC}"
  else
    echo -e "${RED}Error: No se ha podido renombrar.${NC}"
    remove_temporary_dir
    exit 1
  fi
}

remove_temporary_dir() {
  if [ -d "$TEMPORARY_DIR" ]; then
    rm -rf "$TEMPORARY_DIR"
  fi
  echo -e "${GREEN}OK.${NC}"
}

ASSETS="assets"
COMPONENTS="components"
STRINGS="strings"
COLORS="colors"
DIMENS="dimens"

read_configuration() {
  # Verificar si el fichero existe
  FILE="$TEMPORARY_DIR/${MODULES_PATH}${MODULE_NAME}/configuration.gula"
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
    path=$(echo "$line" | cut -d'/' -f2-)
    
    if [ "$type" == "libraries" ]; then
      install_library $path
    elif [[ "$type" == "drawables" || "$type" == "strings" ]]; then
      extension="${path##*.}"
      # Eliminar la extensión del archivo para procesar el resto de la ruta
      path_without_extension="${path%.*}"
      # Reemplazar los puntos por barras en la parte de la ruta
      transformed_path=$(echo "$path_without_extension" | sed 's/\./\//g')
      # Volver a agregar la extensión al final
      final_path="$transformed_path.$extension"
      decide_what_to_do_with_file $type $final_path
    else
      # Reemplazar los puntos por barras
      transformed_path=$(echo "$path" | sed 's/\./\//g')
      # Mostrar el tipo y la ruta transformada
      decide_what_to_do_with_file $type $transformed_path
    fi
    
  done < "$FILE"
}

check_path_exists() {
  local path=$1
  if [ -e "$path" ]; then
    return 0  # Éxito
  else
    return 1  # Error
  fi
}

decide_what_to_do_with_file() {
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

copy_file() {
  local origin=$1
  local destination=$2
  if check_path_exists "$destination"; then   
    echo -e "${YELLOW}$destination ya existe en el proyecto destino.${NC}" 
	read -p "¿Deseas actualizar el módulo existente? (s/n): " CONFIRM < /dev/tty

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
    echo -e "${GREEN}OK.${NC}"
  else
    echo -e "${RED}Error: No se pudo copiar el fichero.${NC}"
  fi 
}	

install_library() {
  local type=$1
  echo "Instalando librería: ${path}"
  echo -e "${YELLOW}Esta librería no se va a instalar todavía.${NC}"

  BUILD_GRADLE_PATH="app/build.gradle.kts"  # Cambia esta ruta según el módulo

  # Verificar si el archivo build.gradle existe
  if [ ! -f "$BUILD_GRADLE_PATH" ]; then
    echo "Error: No se encontró el archivo $BUILD_GRADLE_PATH."
    exit 1
  fi

  # add_library_if_missing ${path}
}

add_library_if_missing() {
  local library=$1
  if grep -q "$library" "$BUILD_GRADLE_PATH"; then
    echo "La librería '$library' ya está en $BUILD_GRADLE_PATH."
  else
    echo "Añadiendo '$library' a $BUILD_GRADLE_PATH."
    # Añadir la librería dentro del bloque dependencies {
    sed -i.bak "/dependencies {/a\    implementation	$library" "$BUILD_GRADLE_PATH"
  fi
}

