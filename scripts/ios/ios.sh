#!/bin/bash

MODULES_PATH_IOS="Gula/Modules"


install_ios_module() {
	os_type=$(check_os)
	if [ "$os_type" != "macOS" ]; then
    	echo -e "${RED}Esta funcionalidad solo puede ser ejecutada en macOS.${NC}"
		exit 0
	fi
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Verificar si el módulo ya está instalado
	local is_reinstall=false
	if is_module_installed "ios" "$MODULE_NAME"; then
		if ! handle_module_reinstallation "ios" "$MODULE_NAME" "${BRANCH:-main}"; then
			exit 0  # Usuario canceló la instalación
		fi
		is_reinstall=true
	else
		# Log inicio de operación (solo para nuevas instalaciones)
		log_operation "install" "ios" "$MODULE_NAME" "${BRANCH:-main}" "started"
	fi

	# Variable para controlar si la instalación fue exitosa
	local installation_success=false

	# Función para manejar errores durante la instalación
	handle_installation_error() {
		# Solo registrar error si la instalación no fue marcada como exitosa
		if [ "$installation_success" = false ]; then
			echo -e "${RED}❌ Error durante la instalación del módulo iOS${NC}"
			if [ "$is_reinstall" = true ]; then
				log_operation "reinstall" "ios" "$MODULE_NAME" "${BRANCH:-main}" "error" "Instalación interrumpida o falló"
			else
				log_operation "install" "ios" "$MODULE_NAME" "${BRANCH:-main}" "error" "Instalación interrumpida o falló"
			fi
			remove_temporary_dir
		fi
	}

	# Configurar trap para capturar errores y interrupciones
	trap handle_installation_error ERR EXIT

	get_access_token $KEY "ios"
	
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	if [ -n "${BRANCH:-}" ]; then
		echo -e "🌿 Usando rama: ${YELLOW}$BRANCH${NC}"
		git clone --branch "$BRANCH" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-ios.git" "$TEMPORARY_DIR"
	else
		git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-ios.git" "$TEMPORARY_DIR"
	fi

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP2 - Copiar ficheros al proyecto.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

  MODULE_NAME="$(echo "${MODULE_NAME:0:1}" | tr '[:lower:]' '[:upper:]')${MODULE_NAME:1}"
	DIRECTORY_PATH="${MODULES_PATH_IOS}/${MODULE_NAME}"
	# ruby "${scripts_dir}/ruby/copy_folder.rb" ${TEMPORARY_DIR} ${DIRECTORY_PATH}

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP3 - Comprobación si esta instalado 'xcodeproj'.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	ios_check_xcodeproj

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP4 - Copiar y añadir a xcode.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	ios_copy_and_add_to_xcode

	echo -e "${GREEN}-----------------------------------------------${NC}"
  	echo -e "${GREEN}Proceso finalizado.${NC}"
  	echo -e "${GREEN}-----------------------------------------------${NC}"
  	
  	# Marcar instalación como exitosa antes de la limpieza
  	installation_success=true
  	
  	# Log éxito de instalación
  	if [ "$is_reinstall" = true ]; then
    	log_operation "reinstall" "ios" "$MODULE_NAME" "${BRANCH:-main}" "success"
  	else
    	log_operation "install" "ios" "$MODULE_NAME" "${BRANCH:-main}" "success"
  	fi
  	log_installed_module "ios" "$MODULE_NAME" "${BRANCH:-main}"
  	
  	# Remover trap de error ya que la instalación fue exitosa
  	trap - ERR EXIT
  	
  	remove_temporary_dir
}

list_ios() {
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	get_access_token $KEY "ios"
	
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	if [ -n "${BRANCH:-}" ]; then
		echo -e "🌿 Usando rama: ${YELLOW}$BRANCH${NC}"
		git clone --branch "$BRANCH" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-ios.git" "$TEMPORARY_DIR"
	else
		git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-ios.git" "$TEMPORARY_DIR"
	fi
	
	echo -e "${BOLD}Lista de módulos disponibles:"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	standardized_list_modules "${MODULES_PATH_IOS}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	remove_temporary_dir
}


install_templates_ios() {
  
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Iniciando instalación.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  
  # Log inicio de generación de template
  log_operation "template" "ios" "$MODULE_NAME" "local" "started"
  
  ios_install_all_templates "$MODULE_NAME"

  if [ $? -eq 0 ]; then
  	echo -e "✅ El módulo '$MODULE_NAME' fue generado correctamente."
  	# Log éxito de generación de template
    log_operation "template" "ios" "$MODULE_NAME" "local" "success"
  else
    echo -e "${RED}Error: Algo salió mal al ejecutar ${NC}"
    # Log error de generación de template
    log_operation "template" "ios" "$MODULE_NAME" "local" "error" "Error durante la generación del template"
    exit 1
  fi
}