#!/bin/bash

MODULES_PATH_FLUTTER="lib/modules"

flutter_prerequisites() {
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	  
	ACCESSTOKEN=$(get_bitbucket_access_token $KEY flutter)
	if [ $? -eq 0 ]; then
		echo -e "✅"
	else
		echo -e "${RED}Error: No se ha podido completar la validación KEY incorrecta.${NC}"
		exit 1
	fi
}

list_flutter() {
	flutter_prerequisites
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"
 	clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git"

	DIRECTORY_PATH="${TEMPORARY_DIR}/${MODULES_PATH_FLUTTER}/"
	echo -e "${GREEN}Lista de módulos disponibles:"
	echo -e "${GREEN}-----------------------------------------------"
	ls -l "$DIRECTORY_PATH" | grep '^d' | awk '{print $9}'  
	echo -e "${GREEN}-----------------------------------------------${NC}"
	remove_temporary_dir
}


install_flutter_module() {	
	flutter_prerequisites
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP2 - Copiar ficheros al proyecto.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	flutter_create_modules_dir
    copy_files "${TEMPORARY_DIR}/lib/modules/${MODULE_NAME}" "lib/modules/"

	if [ $? -eq 0 ]; then
		echo -e "✅"
	else
		echo -e "${RED}Error: No se ha podido copiar el módulo ${MODULE_NAME}.${NC}"
		exit 1
	fi
	flutter_read_configuration

	echo -e "${GREEN}-----------------------------------------------${NC}"
  	echo -e "${GREEN}Proceso finalizado.${NC}"
  	echo -e "${GREEN}-----------------------------------------------${NC}"
  	remove_temporary_dir
}

