#!/bin/bash

ANDROID_PROJECT_SRC="app/src/main/java"
GULA_PACKAGE="app.gula.com"
MODULES_PATH="modules"

list_android() {
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Prerequisitos: Validando.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"

  get_access_token $KEY "android"
  
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"

  git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-android.git" "$TEMPORARY_DIR"
  echo ""
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Lista de módulos disponibles:"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo ""
  android_list_modules "${TEMPORARY_DIR}/${MODULES_PATH}"
  echo ""
  echo -e "${BOLD}-----------------------------------------------${NC}"

  remove_temporary_dir
}

install_android_module() {
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Prerequisitos: Validando.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"

  get_access_token $KEY "android"
  
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  
  if [ -n "${BRANCH:-}" ]; then
    echo -e "🌿 Usando rama: ${YELLOW}$BRANCH${NC}"
    git clone --branch "$BRANCH" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-android.git" "$TEMPORARY_DIR"
  else
    git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-android.git" "$TEMPORARY_DIR"
  fi

  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP2 - Localizar package name del proyecto.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  
  android_detect_package_name 

  # Verificar que el módulo existe en el repositorio clonado
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP3 - Verificación de la existencia del módulo: ${MODULE_NAME}.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  android_check_module_in_temporary_dir $MODULE_NAME

  # Verificar si el módulo ya está instalado en el proyecto destino
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP4 - Verificación instalación previa del módulo: ${MODULE_NAME}.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  android_verify_module $MODULE_NAME
  
  # Verificar si la carpeta 'modules' existe; si no, crearla
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP5 - Verificación existencia carpeta: ${MODULE_NAME}.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  android_create_modules_dir

  # Copiar el módulo al proyecto destino
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP6 - Copiar ficheros al proyecto.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${YELLOW}Inicio copiado de del módulo ${TEMPORARY_DIR}/${MODULE_NAME} en: ${MODULE_NAME}${NC}"
  copy_files "${TEMPORARY_DIR}/${MODULE_NAME}" "."

   # Renombrar los imports en los archivos .java y .kt del módulo copiado
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP7 - Renombrar imports.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  # android_rename_imports

  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP8 - Instalar dependencias principales.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  android_install_main_dependencies

  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP9 - Copiar/instalar las dependencias.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  android_install_libraries_dependencies "$TEMPORARY_DIR/${MODULE_NAME}/configuration.gula"
  android_install_gradle_dependencies "$TEMPORARY_DIR/${MODULE_NAME}/configuration.gula"
  android_install_modules_dependencies

  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP10 - Eliminación repositorio temporal.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  remove_temporary_dir
  
  echo -e "${GREEN}-----------------------------------------------${NC}"
  echo -e "${GREEN}Proceso finalizado.${NC}"
  echo -e "${GREEN}-----------------------------------------------${NC}"
}

install_templates_android() {
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Iniciando instalación de templates Android.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  android_install_all_templates "$MODULE_NAME"

  if [ $? -eq 0 ]; then
    echo -e "✅ El template '$MODULE_NAME' fue generado correctamente."
  else
    echo -e "${RED}Error: Algo salió mal al ejecutar ${NC}"
    exit 1
  fi
}