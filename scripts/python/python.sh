#!/bin/bash

# Obtener directorio del script actual
PYTHON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_INSTALL_SCRIPT="${PYTHON_SCRIPT_DIR}/python_install.py"
SOURCE_DIR="features"

list_python() {
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Log operación de listado
	log_operation "list" "python" "modules" "${BRANCH:-main}" "started"

	GULA_COMMAND="list"
	get_access_token $KEY "back"

	# Intentar obtener módulos permitidos del backend
	local allowed_modules=$(get_allowed_modules "$KEY" "back")
	local get_modules_result=$?

	# Si el backend devuelve módulos filtrados, mostrarlos sin clonar
	if [ $get_modules_result -eq 0 ] && [ "$allowed_modules" != "UNRESTRICTED" ] && [ "$allowed_modules" != "FALLBACK_TO_OLD_METHOD" ]; then
		echo ""
		echo -e "${GREEN}✅ Usando lista de módulos desde el servidor${NC}"
		echo -e "${BOLD}Lista de módulos disponibles:"
		echo -e "${BOLD}-----------------------------------------------${NC}"
		echo "$allowed_modules"
		echo -e "${BOLD}-----------------------------------------------${NC}"
		log_operation "list" "python" "modules" "${BRANCH:-main}" "success"
		return 0
	fi

	# Si no hay módulos permitidos
	if [ "$allowed_modules" = "NO_MODULES_ALLOWED" ]; then
		echo ""
		echo -e "${RED}⚠️  Tu cuenta no tiene acceso a ningún módulo de Python${NC}"
		echo -e "${RED}   Contacta con el administrador para obtener permisos${NC}"
		log_operation "list" "python" "modules" "${BRANCH:-main}" "error" "no_modules_allowed"
		return 1
	fi

	# Si unrestricted o fallback, usar método tradicional (clonar repo)
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	cleanup_temp_directory

	if [ -n "${TAG:-}" ]; then
		echo -e "🏷️  Usando tag: ${YELLOW}$TAG${NC}"
		git clone --branch "$TAG" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git" "$TEMPORARY_DIR"
	elif [ -n "${BRANCH:-}" ]; then
		echo -e "🌿 Usando rama: ${YELLOW}$BRANCH${NC}"
		git clone --branch "$BRANCH" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git" "$TEMPORARY_DIR"
	else
		git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git" "$TEMPORARY_DIR"
	fi

	echo -e "${BOLD}Lista de módulos disponibles:"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Usar el script Python para listar
	python3 "$PYTHON_INSTALL_SCRIPT" list "$TEMPORARY_DIR"

	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Log éxito del listado
	log_operation "list" "python" "modules" "${BRANCH:-main}" "success"

	remove_temporary_dir
}

python_verify_module() {
	local module=$1

	# Verificar si el módulo está en .gula.log (ya manejado por handle_module_reinstallation)
	# Esta función solo verifica archivos específicos del módulo en el proyecto

	# Buscar archivos específicos del módulo en directorios de arquitectura hexagonal
	local module_files_found=false

	# Buscar en driving/api/routers, driven/repositories, domain/models, etc.
	if [ -f "driving/api/routers/${module}_router.py" ] || \
	   [ -f "driven/repositories/${module}_repository.py" ] || \
	   [ -d "domain/models/${module}" ] || \
	   [ -d "application/services/${module}" ]; then
		module_files_found=true
	fi

	if [ "$module_files_found" = true ]; then
		echo -e "${YELLOW}El módulo $module ya existe en el proyecto destino.${NC}"

		# Si --force está activo, no preguntar
		if [ "$FORCE_INSTALL" == "true" ]; then
			echo -e "${GREEN}🔄 Actualizando con --force...${NC}"
		else
			read -p "¿Deseas actualizar el módulo existente? (s/n): " CONFIRM
			if [ "$CONFIRM" != "s" ]; then
				echo -e "${RED}Instalación del módulo cancelada.${NC}"
				exit 0
			fi
		fi
		echo -e "✅ Actualización en curso"
	else
		echo -e "✅ Módulo no detectado, continúa la instalación"
	fi
}

install_python_module() {
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
			exit 1
		fi
	}

	# Configurar trap para capturar errores e interrupciones (Ctrl+C)
	trap 'handle_installation_error; exit 1' ERR INT TERM
	trap 'handle_installation_error' EXIT

	GULA_COMMAND="install"
	get_access_token "$KEY" "back"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	cleanup_temp_directory

	if [ -n "${TAG:-}" ]; then
		echo -e "🏷️  Usando tag: ${YELLOW}$TAG${NC}"
		git clone --branch "$TAG" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git" "$TEMPORARY_DIR"
	elif [ -n "${BRANCH:-}" ]; then
		echo -e "🌿 Usando rama: ${YELLOW}$BRANCH${NC}"
		git clone --branch "$BRANCH" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git" "$TEMPORARY_DIR"
	else
		git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git" "$TEMPORARY_DIR"
	fi

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP2 - Verificación de la existencia del módulo: ${MODULE_NAME}.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Verificar que el módulo existe en el repositorio clonado
	if [ ! -d "$TEMPORARY_DIR/$SOURCE_DIR/$MODULE_NAME" ]; then
		echo -e "${RED}❌ Error: El módulo $MODULE_NAME no existe en el repositorio.${NC}"
		echo -e "${RED}   No encontrado en: $TEMPORARY_DIR/$SOURCE_DIR/$MODULE_NAME${NC}"
		echo ""
		echo -e "${YELLOW}Módulos disponibles:${NC}"
		python3 "$PYTHON_INSTALL_SCRIPT" list "$TEMPORARY_DIR"
		log_operation "install" "python" "$MODULE_NAME" "${BRANCH:-main}" "error" "Módulo no encontrado"
		remove_temporary_dir
		exit 1
	fi
	echo -e "✅ Módulo existe correctamente"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP3 - Verificación instalación previa del módulo: ${MODULE_NAME}.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	python_verify_module "$MODULE_NAME"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP4 - Copiar ficheros al proyecto.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Ejecutar el script Python de instalación
	local verbose_flag=""
	if [ "${VERBOSE:-false}" == "true" ]; then
		verbose_flag="--verbose"
	fi

	python3 "$PYTHON_INSTALL_SCRIPT" install "$TEMPORARY_DIR" "$MODULE_NAME" $verbose_flag

	if [ $? -ne 0 ]; then
		echo -e "${RED}❌ Error durante la instalación del módulo${NC}"
		exit 1
	fi

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP5 - Sincronizar dependencias.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Verificar si hay pyproject.toml y ejecutar uv/pip
	if [ -f "pyproject.toml" ]; then
		if command -v uv &> /dev/null; then
			echo -e "${YELLOW}Ejecutando uv sync...${NC}"
			uv sync 2>/dev/null || true
		elif command -v pip &> /dev/null; then
			echo -e "${YELLOW}Ejecutando pip install...${NC}"
			pip install -e . 2>/dev/null || true
		fi
	fi
	echo -e "✅ Dependencias sincronizadas"

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
	trap - ERR INT TERM EXIT

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP6 - Eliminación repositorio temporal.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	remove_temporary_dir
}

install_python_modules_batch() {
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Instalación BATCH de ${#MODULE_NAMES[@]} módulos Python${NC}"
	echo -e "${BOLD}Módulos: ${MODULE_NAMES[*]}${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}Prerequisitos: Validando KEY.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	# Variable para controlar si la instalación fue exitosa
	local installation_success=false
	local modules_installed=()

	# Función para manejar errores durante la instalación
	handle_installation_error_batch() {
		if [ "$installation_success" = false ]; then
			echo -e "${RED}❌ Error durante la instalación batch de módulos Python${NC}"
			for module in "${modules_installed[@]}"; do
				log_operation "install" "python" "$module" "${BRANCH:-main}" "error" "Instalación batch interrumpida"
			done
			remove_temporary_dir
			exit 1
		fi
	}

	# Configurar trap para capturar errores e interrupciones (Ctrl+C)
	trap 'handle_installation_error_batch; exit 1' ERR INT TERM
	trap 'handle_installation_error_batch' EXIT

	GULA_COMMAND="install"
	get_access_token "$KEY" "back"

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP1 - Clonación temporal del proyecto de GULA.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	cleanup_temp_directory

	if [ -n "${TAG:-}" ]; then
		echo -e "🏷️  Usando tag: ${YELLOW}$TAG${NC}"
		git clone --branch "$TAG" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git" "$TEMPORARY_DIR"
	elif [ -n "${BRANCH:-}" ]; then
		echo -e "🌿 Usando rama: ${YELLOW}$BRANCH${NC}"
		git clone --branch "$BRANCH" "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git" "$TEMPORARY_DIR"
	else
		git clone "https://x-token-auth:$ACCESSTOKEN@bitbucket.org/rudoapps/gula-python.git" "$TEMPORARY_DIR"
	fi

	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP2 - Copiar ficheros de todos los módulos.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	local verbose_flag=""
	if [ "${VERBOSE:-false}" == "true" ]; then
		verbose_flag="--verbose"
	fi

	# Iterar sobre cada módulo
	for MODULE_NAME in "${MODULE_NAMES[@]}"; do
		echo ""
		echo -e "${YELLOW}📦 Procesando módulo: ${BOLD}$MODULE_NAME${NC}"

		# Verificar si el módulo ya está instalado
		local is_reinstall=false
		if is_module_installed "python" "$MODULE_NAME"; then
			if ! handle_module_reinstallation "python" "$MODULE_NAME" "${BRANCH:-main}"; then
				echo -e "${YELLOW}⏭️  Saltando módulo $MODULE_NAME${NC}"
				continue
			fi
			is_reinstall=true
		else
			log_operation "install" "python" "$MODULE_NAME" "${BRANCH:-main}" "started"
		fi

		# Verificar que el módulo existe en el repositorio clonado
		if [ ! -d "$TEMPORARY_DIR/$SOURCE_DIR/$MODULE_NAME" ]; then
			echo -e "${RED}❌ Error: Módulo $MODULE_NAME no encontrado en el repositorio${NC}"
			log_operation "install" "python" "$MODULE_NAME" "${BRANCH:-main}" "error" "Módulo no encontrado"
			continue
		fi

		modules_installed+=("$MODULE_NAME")

		# Ejecutar el script Python de instalación
		python3 "$PYTHON_INSTALL_SCRIPT" install "$TEMPORARY_DIR" "$MODULE_NAME" $verbose_flag

		if [ $? -eq 0 ]; then
			echo -e "${GREEN}✅ Módulo $MODULE_NAME instalado${NC}"
		else
			echo -e "${RED}❌ Error instalando módulo $MODULE_NAME${NC}"
			log_operation "install" "python" "$MODULE_NAME" "${BRANCH:-main}" "error" "Error durante instalación"
		fi
	done

	echo ""
	echo -e "${BOLD}-----------------------------------------------${NC}"
	echo -e "${BOLD}STEP3 - Sincronizar dependencias.${NC}"
	echo -e "${BOLD}-----------------------------------------------${NC}"

	if [ -f "pyproject.toml" ]; then
		if command -v uv &> /dev/null; then
			echo -e "${YELLOW}Ejecutando uv sync...${NC}"
			uv sync 2>/dev/null || true
		elif command -v pip &> /dev/null; then
			echo -e "${YELLOW}Ejecutando pip install...${NC}"
			pip install -e . 2>/dev/null || true
		fi
	fi
	echo -e "✅ Dependencias sincronizadas"

	echo -e "${GREEN}-----------------------------------------------${NC}"
	echo -e "${GREEN}Proceso batch finalizado. ${#modules_installed[@]} módulos instalados.${NC}"
	echo -e "${GREEN}-----------------------------------------------${NC}"

	# Marcar instalación como exitosa
	installation_success=true

	# Log éxito de cada módulo instalado
	for MODULE_NAME in "${modules_installed[@]}"; do
		log_operation "install" "python" "$MODULE_NAME" "${BRANCH:-main}" "success"
		log_installed_module "python" "$MODULE_NAME" "${BRANCH:-main}"
	done

	# Remover trap de error ya que la instalación fue exitosa
	trap - ERR INT TERM EXIT

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
