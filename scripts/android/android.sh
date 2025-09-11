#!/bin/bash

ANDROID_PROJECT_SRC="app/src/main/java"
GULA_PACKAGE="app.gula.com"
MODULES_PATH="modules"

list_android() {
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Prerequisitos: Validando.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"

  # Log operación de listado
  log_operation "list" "android" "modules" "${BRANCH:-main}" "started"

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
  echo ""
  echo -e "${BOLD}Lista de módulos disponibles:"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  standardized_list_modules "" "app" "gradle" "shared"
  echo -e "${BOLD}-----------------------------------------------${NC}"

  # Log éxito del listado
  log_operation "list" "android" "modules" "${BRANCH:-main}" "success"

  remove_temporary_dir
}

install_android_module() {
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Prerequisitos: Validando.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"

  # Verificar si el módulo ya está instalado
  local is_reinstall=false
  if is_module_installed "android" "$MODULE_NAME"; then
    if ! handle_module_reinstallation "android" "$MODULE_NAME" "${BRANCH:-main}"; then
      exit 0  # Usuario canceló la instalación
    fi
    is_reinstall=true
  else
    # Log inicio de operación (solo para nuevas instalaciones)
    log_operation "install" "android" "$MODULE_NAME" "${BRANCH:-main}" "started"
  fi

  # Variable para controlar si la instalación fue exitosa
  local installation_success=false

  # Función para manejar errores durante la instalación
  handle_installation_error() {
    # Solo registrar error si la instalación no fue marcada como exitosa
    if [ "$installation_success" = false ]; then
      echo -e "${RED}❌ Error durante la instalación del módulo Android${NC}"
      if [ "$is_reinstall" = true ]; then
        log_operation "reinstall" "android" "$MODULE_NAME" "${BRANCH:-main}" "error" "Instalación interrumpida o falló"
      else
        log_operation "install" "android" "$MODULE_NAME" "${BRANCH:-main}" "error" "Instalación interrumpida o falló"
      fi
      remove_temporary_dir
    fi
  }

  # Configurar trap para capturar errores y interrupciones
  trap handle_installation_error ERR EXIT

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

  echo -e "${GREEN}-----------------------------------------------${NC}"
  echo -e "${GREEN}Proceso finalizado.${NC}"
  echo -e "${GREEN}-----------------------------------------------${NC}"
  
  # Marcar instalación como exitosa antes de la limpieza
  installation_success=true
  
  # Log éxito de instalación
  if [ "$is_reinstall" = true ]; then
    log_operation "reinstall" "android" "$MODULE_NAME" "${BRANCH:-main}" "success"
  else
    log_operation "install" "android" "$MODULE_NAME" "${BRANCH:-main}" "success"
  fi
  log_installed_module "android" "$MODULE_NAME" "${BRANCH:-main}"
  
  # Remover trap de error ya que la instalación fue exitosa
  trap - ERR EXIT
  
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP10 - Eliminación repositorio temporal.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  remove_temporary_dir
}

install_templates_android() {
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Iniciando instalación de templates Android.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  
  # Log inicio de generación de template
  log_operation "template" "android" "$MODULE_NAME" "local" "started"
  
  android_install_all_templates "$MODULE_NAME"

  if [ $? -eq 0 ]; then
    echo -e "✅ El template '$MODULE_NAME' fue generado correctamente."
    # Log éxito de generación de template
    log_operation "template" "android" "$MODULE_NAME" "local" "success"
  else
    echo -e "${RED}Error: Algo salió mal al ejecutar ${NC}"
    # Log error de generación de template
    log_operation "template" "android" "$MODULE_NAME" "local" "error" "Error durante la generación del template"
    exit 1
  fi
}