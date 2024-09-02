#!/bin/bash

ios_install_package() {
    ruby <<RUBY
require 'xcodeproj'
puts "asdf"
project_path = '$XCODEPROJ_PATH'
package_url = '$PACKAGE_URL'

# Cargar el proyecto Xcode
project = Xcodeproj::Project.open(project_path)

# Obtener el primer target principal (es posible que desees ajustar esto)
main_target = project.targets.first
puts "Main target: #{main_target.name}"

# Añadir el paquete Swift (esto es un pseudo código, Xcodeproj no tiene soporte nativo para Swift Package Manager)
# Deberías gestionar la inclusión del paquete por otro método o agregar manualmente al proyecto.
# Por ejemplo, podrías modificar Package.swift o la estructura del proyecto directamente.
main_target.add_package_dependency(url: package_url)

# Guardar cambios en el proyecto Xcode
project.save
RUBY
}
