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

	get_access_token $KEY "ios"
	
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-ios.git" "temp-gula"

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

 	git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-ios.git" "temp-gula"
	
	echo -e "${GREEN}Lista de módulos disponibles:"
	echo -e "${GREEN}-----------------------------------------------"
	ls -l "${TEMPORARY_DIR}/${MODULES_PATH_IOS}/" | grep '^d' | awk '{print $9}'  
	echo -e "${GREEN}-----------------------------------------------${NC}"

	remove_temporary_dir
}


install_templates_ios() {
  
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Iniciando instalación.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  ios_install_all_templates "$MODULE_NAME"

  if [ $? -eq 0 ]; then
  	echo -e "✅ El módulo '$MODULE_NAME' fue generado correctamente."
  else
    echo -e "${RED}Error: Algo salió mal al ejecutar ${NC}"
    exit 1
  fi
}