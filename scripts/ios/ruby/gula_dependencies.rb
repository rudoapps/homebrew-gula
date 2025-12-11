#!/usr/bin/env ruby
require 'json'

def read_gula_file_and_install_dependencies(xcodeproj_path, app_name, folder_path, temporary_dir, xcode_version)
  gula_file = Dir.glob("#{folder_path}/*.gula").first
  
  if gula_file.nil?
    puts "❌ No se encontró ningún archivo .gula en la carpeta '#{folder_path}'."
  else

    file = File.read(gula_file)
    data = JSON.parse(file)

    items_to_copy = []
    Array(data['shared']).each do |shared_item|
      items_to_copy << shared_item
    end

    if items_to_copy.empty?
      puts "⚠️ No se encontraron elementos"
    end

    if items_to_copy.size > 0
      puts"-----------------------------------------------"
      puts "Dependencias encontradas"
      puts"-----------------------------------------------"
      items_to_copy.each do |item|
        puts "📦 #{item}"  
      end
      for item in items_to_copy do
        # Eliminar "Shared/" de la ruta para integrar directamente en las capas
        copy_all_files("#{temporary_dir}/#{item}", item.sub("Gula/Shared", app_name))
      end
      if xcode_version == 15
        # Crear grupos para cada subcarpeta de Shared integrada
        items_to_copy.each do |item|
          layer = item.sub("Gula/Shared/", "").split("/").first
          destination = "#{app_name}/#{layer}"
          if Dir.exist?(destination)
            create_groups(xcodeproj_path, app_name, destination, layer)
          end
        end
      end
    end 

    puts"-----------------------------------------------"
    puts "Instalando librerías"
    puts"-----------------------------------------------"

    Array(data['libraries']).each do |library|
      name = library['name']
      url = library['url']
      version = library['version']
      
      install_packages(xcodeproj_path, name, url, version)
    end
  end
end

def install_packages(xcodeproj_path, name, url, version)
  project = Xcodeproj::Project.open(xcodeproj_path)
  target = project.targets.first

  found = false
  if project.objects.count > 0
    project.objects.each do |object|
      next unless object.is_a?(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
      if object.repositoryURL.downcase == url.downcase
        puts "❌ #{name} (#{object.display_name}) ya esta instalado"
        found = true
        break
      end
    end

    if !found
      swift_package = project.new Xcodeproj::Project::Object::XCRemoteSwiftPackageReference
      swift_package.repositoryURL = url
      swift_package.requirement = {
        "kind" => "upToNextMajorVersion",
        "minimumVersion" => version
      }
      swift_package_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
      swift_package_product.package = swift_package
      swift_package_product.product_name = name

      target.package_product_dependencies << swift_package_product

      project.root_object.package_references << swift_package

      project.save
      puts "✅ Librería: #{name}, URL: #{url}, Versión: #{version}"
    end
  end 
end
