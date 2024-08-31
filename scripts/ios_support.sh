#!/bin/bash
ios_install_package() {
	swift package resolve
	ruby <<RUBY
	require 'xcodeproj'

	project_path = '$XCODEPROJ_PATH'
	package_url = '$PACKAGE_URL'

	# Cargar el proyecto Xcode
	project = Xcodeproj::Project.open(project_path)

	# Crear o encontrar la sección de dependencias
	main_target = project.targets.first
	dependencies_group = project.main_group.find_subpath("Dependencies", true)

	# Añadir el paquete Swift
	main_target.add_package_dependency(url: package_url)

	# Guardar cambios
	project.save
	RUBY
}

