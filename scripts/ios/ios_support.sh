#!/bin/bash

prerequisites() {
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

