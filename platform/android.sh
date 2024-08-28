#!/bin/bash

list_android() {
  clone "https://x-token-auth:$KEY@bitbucket.org/rudoapps/gula-android.git"
  DIRECTORY_PATH="${TEMPORARY_DIR}/${MODULES_PATH}"
  echo -e "${GREEN}Lista de módulos disponibles:"
  echo -e "${GREEN}-----------------------------------------------"
  ls -l "$DIRECTORY_PATH" | grep '^d' | awk '{print $9}'  
  echo -e "${GREEN}-----------------------------------------------${NC}"
  remove_temporary_dir
}

install_android_module() {
  MODULE_NAME="$1"

  # STEP1
  # Verificar si la ruta base existe
  echo -e "${YELLOW}STEP1 - Localizar package name del proyecto.${NC}"
  detect_package_name

  # Clonamos el repositorio a una carpeta temporal
  echo -e "${YELLOW}STEP2 - Clonación temporal del proyecto de GULA.${NC}"
  clone "https://x-token-auth:$KEY@bitbucket.org/rudoapps/gula-android.git"

  # Verificar que el módulo existe en el repositorio clonado
  echo -e "${YELLOW}STEP3 - Verificación de la existencia del módulo: ${MODULE_NAME}.${NC}"
  check_module_in_temporary_dir

  # Verificar si el módulo ya está instalado en el proyecto destino
  echo -e "${YELLOW}STEP4 - Verificación instalación previa del módulo: ${MODULE_NAME}.${NC}"
  verify_module
  
  # Verificar si la carpeta 'modules' existe; si no, crearla
  echo -e "${YELLOW}STEP5 - Verificación existencia carpeta: ${MODULE_NAME}.${NC}"
  create_modules_dir

  # Copiar el módulo al proyecto destino
  echo -e "${YELLOW}STEP6 - Copiar ficheros al proyecto.${NC}"
  copy_files

   # Renombrar los imports en los archivos .java y .kt del módulo copiado
  echo -e "${YELLOW}STEP7 - Renombrar imports.${NC}"
  rename_imports

  echo -e "${YELLOW}STEP8 - Eliminación repositorio temporal.${NC}"
  remove_temporary_dir
  
  echo -e "${GREEN}-----------------------------------------------${NC}"
  echo -e "${GREEN}Proceso finalizado.${NC}"
  echo -e "${GREEN}-----------------------------------------------${NC}"
}