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
  # STEP1
  # Verificar si la ruta base existe
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP1 - Localizar package name del proyecto.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  detect_package_name

  # Clonamos el repositorio a una carpeta temporal
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP2 - Clonación temporal del proyecto de GULA.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  clone "https://x-token-auth:$KEY@bitbucket.org/rudoapps/gula-android.git"

  # Verificar que el módulo existe en el repositorio clonado
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP3 - Verificación de la existencia del módulo: ${MODULE_NAME}.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  check_module_in_temporary_dir

  # Verificar si el módulo ya está instalado en el proyecto destino
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP4 - Verificación instalación previa del módulo: ${MODULE_NAME}.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  verify_module
  
  # Verificar si la carpeta 'modules' existe; si no, crearla
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP5 - Verificación existencia carpeta: ${MODULE_NAME}.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  create_modules_dir

  # Copiar el módulo al proyecto destino
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP6 - Copiar ficheros al proyecto.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  copy_files

   # Renombrar los imports en los archivos .java y .kt del módulo copiado
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP7 - Renombrar imports.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  rename_imports

  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP8 - Copiar/instalar las dependencias.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  read_configuration

  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP9 - Eliminación repositorio temporal.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  remove_temporary_dir
  
  echo -e "${GREEN}-----------------------------------------------${NC}"
  echo -e "${GREEN}Proceso finalizado.${NC}"
  echo -e "${GREEN}-----------------------------------------------${NC}"
}