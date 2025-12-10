#!/bin/bash

MODULES_PATH_FLUTTER="lib/modules"

install_flutter_modules_batch() {
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Instalación BATCH de ${#MODULE_NAMES[@]} módulos Flutter${NC}"
	echo -e "${BOLD}Módulos: ${MODULE_NAMES[*]}${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando KEY.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Variable para controlar si la instalación fue exitosa
	local installation_success=false
	local modules_installed=()

	# Función para manejar errores durante la instalación
	handle_installation_error() {
		if [ "$installation_success" = false ]; then
			echo -e "${RED}❌ Error durante la instalación batch de módulos Flutter${NC}"
			for module in "${modules_installed[@]}"; do
				log_operation "install" "flutter" "$module" "${BRANCH:-main}" "error" "Instalación batch interrumpida"
			done
			remove_temporary_dir
		fi
	}

	# Configurar trap para capturar errores y interrupciones
	trap handle_installation_error ERR EXIT

	GULA_COMMAND="install"
	get_access_token $KEY "flutter"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	if [ -d "$TEMPORARY_DIR" ]; then
		echo "🗑️ Borrando directorio existente: $TEMPORARY_DIR"
		rm -rf "$TEMPORARY_DIR"
	fi

	if [ -n "${TAG:-}" ]; then
		echo -e "🏷️  Usando tag: ${YELLOW}$TAG${NC}"
		git clone --branch "$TAG" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git" "$TEMPORARY_DIR"
	elif [ -n "${BRANCH:-}" ]; then
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
	echo -e "${BOLD}STEP3 - Copiar ficheros de todos los módulos.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	flutter_create_modules_dir

	# Iterar sobre cada módulo
	for MODULE_NAME in "${MODULE_NAMES[@]}"; do
		echo ""
		echo -e "${YELLOW}📦 Procesando módulo: ${BOLD}$MODULE_NAME${NC}"

		# Verificar si el módulo ya está instalado
		local is_reinstall=false
		if is_module_installed "flutter" "$MODULE_NAME"; then
			if ! handle_module_reinstallation "flutter" "$MODULE_NAME" "${BRANCH:-main}"; then
				echo -e "${YELLOW}⏭️  Saltando módulo $MODULE_NAME${NC}"
				continue
			fi
			is_reinstall=true
		else
			log_operation "install" "flutter" "$MODULE_NAME" "${BRANCH:-main}" "started"
		fi

		modules_installed+=("$MODULE_NAME")

		# Copiar archivos del módulo (detectar si está en plugins o lib/modules)
		if [ -d "${TEMPORARY_DIR}/plugins/${MODULE_NAME}" ]; then
			echo -e "${YELLOW}📦 Detectado como plugin (en plugins/${MODULE_NAME})${NC}"
			mkdir -p "plugins"
			copy_files "${TEMPORARY_DIR}/plugins/${MODULE_NAME}" "plugins/."
			# Para plugins, pasar path sin lib/ prefix
			if [ -f "${TEMPORARY_DIR}/plugins/${MODULE_NAME}/configuration.gula" ]; then
				flutter_read_configuration "../plugins/${MODULE_NAME}/"
			fi
			echo -e "${GREEN}✅ Plugin $MODULE_NAME copiado${NC}"
		elif [ -d "${TEMPORARY_DIR}/lib/modules/${MODULE_NAME}" ]; then
			echo -e "${YELLOW}📦 Detectado como módulo (en lib/modules/${MODULE_NAME})${NC}"
			copy_files "${TEMPORARY_DIR}/lib/modules/${MODULE_NAME}" "lib/modules/."
			flutter_read_configuration "modules/${MODULE_NAME}/"
			echo -e "${GREEN}✅ Módulo $MODULE_NAME copiado${NC}"
		else
			echo -e "${RED}❌ Error: ${MODULE_NAME} no encontrado ni en plugins/ ni en lib/modules/${NC}"
			log_operation "install" "flutter" "$MODULE_NAME" "${BRANCH:-main}" "error" "Módulo no encontrado"
			continue
		fi
	done

	echo ""
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP4 - Renombrar imports de todos los módulos.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	flutter_rename_imports

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP5 - Actualización de dependencias (una sola vez).${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	echo ""
	flutter clean
	flutter pub get
	echo ""

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP6 - Generando archivo de configuración de DI.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	echo ""
	dart run build_runner build --delete-conflicting-outputs
	echo ""

	echo -e "${GREEN}-----------------------------------------------${NC}"
	echo -e "${GREEN}Proceso batch finalizado. ${#modules_installed[@]} módulos instalados.${NC}"
	echo -e "${GREEN}-----------------------------------------------${NC}"

	# Marcar instalación como exitosa
	installation_success=true

	# Log éxito de cada módulo instalado
	for MODULE_NAME in "${modules_installed[@]}"; do
		log_operation "install" "flutter" "$MODULE_NAME" "${BRANCH:-main}" "success"
		log_installed_module "flutter" "$MODULE_NAME" "${BRANCH:-main}"
	done

	# Remover trap de error ya que la instalación fue exitosa
	trap - ERR EXIT

	remove_temporary_dir
}

list_flutter() {
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	GULA_COMMAND="list"
	get_access_token $KEY "flutter"

	# Intentar obtener módulos permitidos del backend
	local allowed_modules=$(get_allowed_modules "$KEY" "flutter")
	local get_modules_result=$?

	# Si el backend devuelve módulos filtrados, mostrarlos sin clonar
	if [ $get_modules_result -eq 0 ] && [ "$allowed_modules" != "UNRESTRICTED" ] && [ "$allowed_modules" != "FALLBACK_TO_OLD_METHOD" ]; then
		echo ""
		echo -e "${GREEN}✅ Usando lista de módulos desde el servidor${NC}"
		echo -e "${BOLD}Lista de módulos disponibles:"
		echo -e "${BOLD}-----------------------------------------------${NC}"
		echo "$allowed_modules"
		echo -e "${BOLD}-----------------------------------------------${NC}"
		return 0
	fi

	# Si no hay módulos permitidos
	if [ "$allowed_modules" = "NO_MODULES_ALLOWED" ]; then
		echo ""
		echo -e "${RED}⚠️  Tu cuenta no tiene acceso a ningún módulo de Flutter${NC}"
		echo -e "${RED}   Contacta con el administrador para obtener permisos${NC}"
		return 1
	fi

	# Si unrestricted o fallback, usar método tradicional (clonar repo)
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	if [ -n "${TAG:-}" ]; then
		echo -e "🏷️  Usando tag: ${YELLOW}$TAG${NC}"
		git clone --branch "$TAG" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git" "$TEMPORARY_DIR"
	elif [ -n "${BRANCH:-}" ]; then
		echo -e "🌿 Usando rama: ${YELLOW}$BRANCH${NC}"
		git clone --branch "$BRANCH" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git" "$TEMPORARY_DIR"
	else
		git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git" "$TEMPORARY_DIR"
	fi

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

	# Verificar si el módulo ya está instalado
	local is_reinstall=false
	if is_module_installed "flutter" "$MODULE_NAME"; then
		if ! handle_module_reinstallation "flutter" "$MODULE_NAME" "${BRANCH:-main}"; then
			exit 0  # Usuario canceló la instalación
		fi
		is_reinstall=true
	else
		# Log inicio de operación (solo para nuevas instalaciones)
		log_operation "install" "flutter" "$MODULE_NAME" "${BRANCH:-main}" "started"
	fi

	# Variable para controlar si la instalación fue exitosa
	local installation_success=false

	# Función para manejar errores durante la instalación
	handle_installation_error() {
		# Solo registrar error si la instalación no fue marcada como exitosa
		if [ "$installation_success" = false ]; then
			echo -e "${RED}❌ Error durante la instalación del módulo Flutter${NC}"
			if [ "$is_reinstall" = true ]; then
				log_operation "reinstall" "flutter" "$MODULE_NAME" "${BRANCH:-main}" "error" "Instalación interrumpida o falló"
			else
				log_operation "install" "flutter" "$MODULE_NAME" "${BRANCH:-main}" "error" "Instalación interrumpida o falló"
			fi
			remove_temporary_dir
		fi
	}

	# Configurar trap para capturar errores y interrupciones
	trap handle_installation_error ERR EXIT

	GULA_COMMAND="install"
	get_access_token $KEY "flutter"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"
	if [ -d "$TEMPORARY_DIR" ]; then
	  echo "🗑️ Borrando directorio existente: $TEMPORARY_DIR"
	  rm -rf "$TEMPORARY_DIR"
	fi
	
	if [ -n "${TAG:-}" ]; then
		echo -e "🏷️  Usando tag: ${YELLOW}$TAG${NC}"
		git clone --branch "$TAG" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-flutter.git" "$TEMPORARY_DIR"
	elif [ -n "${BRANCH:-}" ]; then
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

	# Detectar si el módulo está en plugins o en lib/modules
	if [ -d "${TEMPORARY_DIR}/plugins/${MODULE_NAME}" ]; then
		echo -e "${YELLOW}📦 Detectado como plugin (en plugins/${MODULE_NAME})${NC}"
		mkdir -p "plugins"
		copy_files "${TEMPORARY_DIR}/plugins/${MODULE_NAME}" "plugins/."
		# Para plugins, pasar path sin lib/ prefix
		if [ -f "${TEMPORARY_DIR}/plugins/${MODULE_NAME}/configuration.gula" ]; then
			flutter_read_configuration "../plugins/${MODULE_NAME}/"
		fi
	elif [ -d "${TEMPORARY_DIR}/lib/modules/${MODULE_NAME}" ]; then
		echo -e "${YELLOW}📦 Detectado como módulo (en lib/modules/${MODULE_NAME})${NC}"
		flutter_create_modules_dir
		copy_files "${TEMPORARY_DIR}/lib/modules/${MODULE_NAME}" "lib/modules/."
		flutter_read_configuration "modules/${MODULE_NAME}/"
	else
		echo -e "${RED}❌ Error: No se encontró ${MODULE_NAME} ni en plugins/ ni en lib/modules/${NC}"
		exit 1
	fi
    
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
  	
  	# Marcar instalación como exitosa antes de la limpieza
  	installation_success=true
  	
  	# Log éxito de instalación
  	if [ "$is_reinstall" = true ]; then
    	log_operation "reinstall" "flutter" "$MODULE_NAME" "${BRANCH:-main}" "success"
  	else
    	log_operation "install" "flutter" "$MODULE_NAME" "${BRANCH:-main}" "success"
  	fi
  	log_installed_module "flutter" "$MODULE_NAME" "${BRANCH:-main}"
  	
  	# Remover trap de error ya que la instalación fue exitosa
  	trap - ERR EXIT
  	
  	remove_temporary_dir
}

install_templates_flutter() {
  echo -e "${BOLD}-----------------------------------------------${NC}"
  echo -e "${BOLD}Iniciando instalación de templates Flutter.${NC}"
  echo -e "${BOLD}-----------------------------------------------${NC}"
  
  # Log inicio de generación de template
  log_operation "template" "flutter" "$MODULE_NAME" "local" "started"
  
  flutter_install_all_templates "$MODULE_NAME"

  if [ $? -eq 0 ]; then
    echo -e "✅ El template '$MODULE_NAME' fue generado correctamente."
    # Log éxito de generación de template
    log_operation "template" "flutter" "$MODULE_NAME" "local" "success"
  else
    echo -e "${RED}Error: Algo salió mal al ejecutar ${NC}"
    # Log error de generación de template
    log_operation "template" "flutter" "$MODULE_NAME" "local" "error" "Error durante la generación del template"
    exit 1
  fi
}

