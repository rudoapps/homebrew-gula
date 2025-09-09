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

	echo -e "${BOLD}Lista de módulos disponibles:"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	standardized_list_modules "${MODULES_PATH_FLUTTER}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

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
	if [ -d "$TEMPORARY_DIR" ]; then
	  echo "🗑️ Borrando directorio existente: $TEMPORARY_DIR"
	  rm -rf "$TEMPORARY_DIR"
	fi
	
	if [ -n "${BRANCH:-}" ]; then
		echo -e "🌿 Usando rama: ${YELLOW}$BRANCH${NC}"
		git clone --branch "$BRANCH" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git" "$TEMPORARY_DIR"
	else
		git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git" "$TEMPORARY_DIR"
	fi

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
    
	#echo -e "${BOLD}-----------------------------------------------${NC}"
	#echo -e "${BOLD}STEP4 - Cargando dependencias.${NC}"
	#echo -e "${BOLD}-----------------------------------------------${NC}"

	#flutter_read_configuration

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP4 - Renombrar imports.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	
	flutter_rename_imports	

	echo -e "${BOLD}-----------------------------------------------${NC}"
  	echo -e "${BOLD}STEP5 - Actualización de dependencias.${NC}"
  	echo -e "${BOLD}-----------------------------------------------${NC}"

  	echo ""
  	flutter clean
  	flutter pub get
  	echo ""

  	echo -e "${BOLD}-----------------------------------------------${NC}"
  	echo -e "${BOLD}STEP6 - Generarando archivo de configuración de DI.${NC}"
  	echo -e "${BOLD}-----------------------------------------------${NC}"

  	echo ""
  	dart run build_runner build --delete-conflicting-outputs
  	echo ""

  	echo -e "${GREEN}-----------------------------------------------${NC}"
  	echo -e "${GREEN}Proceso finalizado.${NC}"
  	echo -e "${GREEN}-----------------------------------------------${NC}"
  	remove_temporary_dir
}

install_templates_flutter() {
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Iniciando instalación de templates Flutter.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  flutter_install_all_templates "$MODULE_NAME"

  if [ $? -eq 0 ]; then
    echo -e "✅ El template '$MODULE_NAME' fue generado correctamente."
  else
    echo -e "${RED}Error: Algo salió mal al ejecutar ${NC}"
    exit 1
  fi
}

