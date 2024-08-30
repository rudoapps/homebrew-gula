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

prerequisites() {
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Prerequisitos: Validando.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  
  ACCESSTOKEN=$(get_bitbucket_access_token $KEY android)
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}OK.${NC}"
  else
    echo -e "${RED}Error: No se ha podido completar la validación KEY incorrecta.${NC}"
    exit 1
  fi
}

install_android_module() {
  prerequisites
  echo $ACCESSTOKEN
  # Clonamos el repositorio a una carpeta temporal
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-android.git"

  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP2 - Localizar package name del proyecto.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  android_detect_package_name 

  # Verificar que el módulo existe en el repositorio clonado
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP3 - Verificación de la existencia del módulo: ${MODULE_NAME}.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  check_module_in_temporary_dir

  # Verificar si el módulo ya está instalado en el proyecto destino
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP4 - Verificación instalación previa del módulo: ${MODULE_NAME}.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  android_verify_module
  
  # Verificar si la carpeta 'modules' existe; si no, crearla
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP5 - Verificación existencia carpeta: ${MODULE_NAME}.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  android_create_modules_dir

  # Copiar el módulo al proyecto destino
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP6 - Copiar ficheros al proyecto.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${YELLOW}Inicio copiado de del módulo ${MODULE_NAME} en: ${MAIN_DIRECTORY}/modules/${MODULE_NAME}${NC}"
  copy_files "${TEMPORARY_DIR}/${MODULES_PATH}${MODULE_NAME}" "${MAIN_DIRECTORY}/modules/"

   # Renombrar los imports en los archivos .java y .kt del módulo copiado
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP7 - Renombrar imports.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  android_rename_imports

  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP8 - Copiar/instalar las dependencias.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  android_read_configuration

  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP9 - Eliminación repositorio temporal.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  remove_temporary_dir
  
  echo -e "${GREEN}-----------------------------------------------${NC}"
  echo -e "${GREEN}Proceso finalizado.${NC}"
  echo -e "${GREEN}-----------------------------------------------${NC}"
}