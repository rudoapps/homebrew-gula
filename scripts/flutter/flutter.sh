#!/bin/bash

MODULES_PATH_FLUTTER="lib/modules"

list_flutter() {
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	get_access_token $KEY "flutter"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

 	git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git" "$TEMPORARY_DIR"

	echo -e "${GREEN}Lista de módulos disponibles:"
	echo -e "${GREEN}-----------------------------------------------"
	ls -l "${TEMPORARY_DIR}/${MODULES_PATH_FLUTTER}/" | grep '^d' | awk '{print $9}'  
	echo -e "${GREEN}-----------------------------------------------${NC}"

	remove_temporary_dir
}


install_flutter_module() {	
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando KEY.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	get_access_token $KEY "flutter"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git" "$TEMPORARY_DIR"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP2 - Instalar dependencias generales.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	flutter_read_versions_and_install_pubspec "lib/"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP3 - Copiar ficheros al proyecto.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	flutter_create_modules_dir
	copy_files "${TEMPORARY_DIR}/lib/modules/${MODULE_NAME}" "lib/modules/."
	flutter_read_configuration "modules/${MODULE_NAME}/"
    
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP4 - Cargando dependencias.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	flutter_read_configuration

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP5 - Renombrar imports.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	
	flutter_rename_imports

	echo -e "${BOLD}-----------------------------------------------${NC}"
  	echo -e "${BOLD}STEP6 - Actualización de dependencias.${NC}"
  	echo -e "${BOLD}-----------------------------------------------${NC}"

  	echo ""
  	flutter pub get
  	echo ""

  	echo -e "${GREEN}-----------------------------------------------${NC}"
  	echo -e "${GREEN}Proceso finalizado.${NC}"
  	echo -e "${GREEN}-----------------------------------------------${NC}"
  	remove_temporary_dir
}

