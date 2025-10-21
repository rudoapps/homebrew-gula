#!/bin/bash


list_python() {
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Log operación de listado
	log_operation "list" "python" "modules" "${BRANCH:-main}" "started"

	GULA_COMMAND="list"
	get_access_token $KEY "back"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	if [ -n "${BRANCH:-}" ]; then
		echo -e "🌿 Usando rama: ${YELLOW}$BRANCH${NC}"
	fi
 	clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git"

	echo -e "${BOLD}Lista de módulos disponibles:"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	standardized_list_modules "features"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Log éxito del listado
	log_operation "list" "python" "modules" "${BRANCH:-main}" "success"

	remove_temporary_dir
}

install_python_module() {
  REQUESTED_MODULES=$1
  echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando KEY.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Verificar si el módulo ya está instalado
	local is_reinstall=false
	if is_module_installed "python" "$MODULE_NAME"; then
		if ! handle_module_reinstallation "python" "$MODULE_NAME" "${BRANCH:-main}"; then
			exit 0  # Usuario canceló la instalación
		fi
		is_reinstall=true
	else
		# Log inicio de operación (solo para nuevas instalaciones)
		log_operation "install" "python" "$MODULE_NAME" "${BRANCH:-main}" "started"
	fi

	# Variable para controlar si la instalación fue exitosa
	local installation_success=false

	# Función para manejar errores durante la instalación
	handle_installation_error() {
		# Solo registrar error si la instalación no fue marcada como exitosa
		if [ "$installation_success" = false ]; then
			echo -e "${RED}❌ Error durante la instalación del módulo Python${NC}"
			if [ "$is_reinstall" = true ]; then
				log_operation "reinstall" "python" "$MODULE_NAME" "${BRANCH:-main}" "error" "Instalación interrumpida o falló"
			else
				log_operation "install" "python" "$MODULE_NAME" "${BRANCH:-main}" "error" "Instalación interrumpida o falló"
			fi
			remove_temporary_dir
		fi
	}

	# Configurar trap para capturar errores y interrupciones
	trap handle_installation_error ERR EXIT

	GULA_COMMAND="install"
	get_access_token "$KEY" "back"

  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"

	deep_clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git"
	install_python_dependencies
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

	# Marcar instalación como exitosa antes de la limpieza
	installation_success=true

	# Log éxito de instalación
	if [ "$is_reinstall" = true ]; then
		log_operation "reinstall" "python" "$MODULE_NAME" "${BRANCH:-main}" "success"
	else
		log_operation "install" "python" "$MODULE_NAME" "${BRANCH:-main}" "success"
	fi
	log_installed_module "python" "$MODULE_NAME" "${BRANCH:-main}"

	# Remover trap de error ya que la instalación fue exitosa
	trap - ERR EXIT

	remove_temporary_dir
}

install_templates_python() {
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Iniciando instalación de templates Python.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  
  # Log inicio de generación de template
  log_operation "template" "python" "$MODULE_NAME" "local" "started"
  
  python_install_all_templates "$MODULE_NAME"

  if [ $? -eq 0 ]; then
    echo -e "✅ El template '$MODULE_NAME' fue generado correctamente."
    # Log éxito de generación de template
    log_operation "template" "python" "$MODULE_NAME" "local" "success"
  else
    echo -e "${RED}Error: Algo salió mal al ejecutar ${NC}"
    # Log error de generación de template
    log_operation "template" "python" "$MODULE_NAME" "local" "error" "Error durante la generación del template"
    exit 1
  fi
}
