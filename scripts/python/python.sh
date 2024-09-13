#!/bin/bash


list_python() {
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	get_access_token $KEY "back"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

 	clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git"

	echo -e "${GREEN}Lista de módulos disponibles:"
	echo -e "${GREEN}-----------------------------------------------"
	ls -l "${TEMPORARY_DIR}/features/" | grep '^d' | awk '{print $9}'  
	echo -e "${GREEN}-----------------------------------------------${NC}"

	remove_temporary_dir
}

install_python_module() {
  REQUESTED_MODULES=$1
  echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando KEY.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	get_access_token "$KEY" "back"

  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"

	clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git"
  create_gula_packages_dir
	build_packages

	echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP2 - Copiar ficheros al proyecto.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo ""

  copy_packages "$REQUESTED_MODULES"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP3 - Instalando paquetes solicitados.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo ""

	install_packages

  echo -e "${GREEN}-----------------------------------------------${NC}"
  echo -e "${GREEN}Paquetes instalados correctamente.${NC}"

	echo -e "${GREEN}-----------------------------------------------${NC}"
  echo -e "${GREEN}Proceso finalizado.${NC}"
  echo -e "${GREEN}-----------------------------------------------${NC}"

	remove_temporary_dir
}
