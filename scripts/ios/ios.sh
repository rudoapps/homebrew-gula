#!/bin/bash

MODULES_PATH_IOS="Gula/Modules"

ios_prerequisites() {
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	ACCESSTOKEN=$(get_bitbucket_access_token $KEY ios)
	if [ $? -eq 0 ]; then
		echo -e "✅"
	else
		echo -e "${RED}Error: No se ha podido completar la validación KEY incorrecta.${NC}"
		exit 1
	fi
}

install_ios_module() {
	os_type=$(check_os)
	if [ "$os_type" != "macOS" ]; then
    	echo -e "${RED}Esta funcionalidad solo puede ser ejecutada en macOS.${NC}"
		exit 0
	fi
	ios_prerequisites
	
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-ios.git"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP2 - Copiar ficheros al proyecto.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"


    MODULE_NAME="$(echo "${MODULE_NAME:0:1}" | tr '[:lower:]' '[:upper:]')${MODULE_NAME:1}"
	DIRECTORY_PATH="${MODULES_PATH_IOS}/${MODULE_NAME}"
	# ruby "${scripts_dir}/ruby/copy_folder.rb" ${TEMPORARY_DIR} ${DIRECTORY_PATH}
	ruby "${scripts_dir}/ruby/copy_and_add_xcode.rb" "${TEMPORARY_DIR}/${DIRECTORY_PATH}" "Modules/${MODULE_NAME}" "${TEMPORARY_DIR}"
	if [ $? -eq 0 ]; then
		echo -e "✅"
	else
		echo -e "${RED}Error: No se ha podido copiar el módulo ${MODULE_NAME}.${NC}"
		exit 1
	fi

	echo -e "${GREEN}-----------------------------------------------${NC}"
  	echo -e "${GREEN}Proceso finalizado.${NC}"
  	echo -e "${GREEN}-----------------------------------------------${NC}"
  	remove_temporary_dir
}

list_ios() {
	ios_prerequisites
	
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"
 	clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-ios.git"

	DIRECTORY_PATH="${TEMPORARY_DIR}/${MODULES_PATH_IOS}/"
	echo -e "${GREEN}Lista de módulos disponibles:"
	echo -e "${GREEN}-----------------------------------------------"
	ls -l "$DIRECTORY_PATH" | grep '^d' | awk '{print $9}'  
	echo -e "${GREEN}-----------------------------------------------${NC}"
	remove_temporary_dir
}