#!/bin/bash

ios_check_xcodeproj() {
	if ! gem list -i xcodeproj > /dev/null 2>&1; then
	  echo "La gema 'xcodeproj' no está instalada. Procediendo con la instalación..."
	  sudo gem install xcodeproj
	  if [ $? -eq 0 ]; then
		echo -e "✅ 'xcodeproj' se ha instalado correctamente"
	  else
		echo -e "${RED}Error: No se ha podido instalar 'xcodeproj' necesaria para continuar ${MODULE_NAME}.${NC}"
		exit 1
	  fi
	else
	  echo "✅ La gema 'xcodeproj' ya está instalada."
	fi
}

ios_copy_and_add_to_xcode() {
	ruby "${scripts_dir}/ios/ruby/copy_and_add_xcode.rb" "${TEMPORARY_DIR}/${DIRECTORY_PATH}" "Modules/${MODULE_NAME}" "${TEMPORARY_DIR}"
	if [ $? -eq 0 ]; then
		echo -e "✅ script de ruby ejecutado correctamente"
	else
		echo -e "${RED}Error: No se ha podido copiar el módulo ${MODULE_NAME}.${NC}"
		exit 1
	fi
}

ios_install_dependencies() {
	local dependencies_file=$1
	json=$(cat $dependencies_file)
	# Recorrer el array 'shared'
	echo "Recorriendo 'shared':"
	echo "$json" | jq -r '.shared[]' | while read shared_item; do
	  echo "Elemento compartido: $shared_item"
	done

	# Recorrer el array 'libraries' y obtener cada campo
	echo "Recorriendo 'libraries':"
	echo "$json" | jq -c '.libraries[]' | while read library; do
	  name=$(echo "$library" | jq -r '.name')
	  url=$(echo "$library" | jq -r '.url')
	  version=$(echo "$library" | jq -r '.version')
	  echo "Librería: $name, URL: $url, Versión: $version"
	done
}