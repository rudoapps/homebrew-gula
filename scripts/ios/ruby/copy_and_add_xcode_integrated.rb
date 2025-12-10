#!/usr/bin/env ruby

require 'xcodeproj'
require 'fileutils'
require_relative 'gula_dependencies.rb'

def xcode_version
  version_output = `xcodebuild -version`
  version = version_output.lines.first.strip.split(' ').last
  puts "ℹ️  Xcode Version: #{version}"
  version
end

def check_object_version(xcodeproj_path)
  pbxproj_path = "#{xcodeproj_path}/project.pbxproj"
  object_version_line = File.readlines(pbxproj_path).grep(/objectVersion/).first

  if object_version_line
    object_version = object_version_line.scan(/\d+/).first.to_i
    puts "ℹ️  Object Version: #{object_version}"

    if object_version > 76
      puts "✅ Proyecto creado con xcode 16+"
      return 16
    else
      puts "✅ Proyecto creado con xcode 15 o inferior."
      return 15
    end
  else
    puts "❌ No se encontró 'objectVersion' en el archivo."
    exit 1
  end
end

def find_xcode_project_and_app_name
  xcode_project_path = Dir.glob("*.xcodeproj").first
  if xcode_project_path.nil?
    puts "❌ No se encontró ningún archivo .xcodeproj en el directorio actual."
    exit 1
  end
  app_name = File.basename(xcode_project_path, ".xcodeproj")
  puts "✅ Proyecto Xcode encontrado: #{xcode_project_path} (Aplicación: #{app_name})"
  return xcode_project_path, app_name
end

def copy_all_files(origin, destination)
  return unless Dir.exist?(origin)

  FileUtils.mkdir_p(destination)
  Dir.glob("#{origin}/**/*").each do |item|
    relative_path = item.sub("#{origin}/", "")
    destination_path = File.join(destination, relative_path)
    if File.directory?(item)
      FileUtils.mkdir_p(destination_path)
    else
      FileUtils.mkdir_p(File.dirname(destination_path))
      FileUtils.cp(item, destination_path)
      puts "✅ Código añadido en: #{destination_path}"
    end
  end
end

def create_groups(xcodeproj_path, app_name, destination, destination_relative_path)
  project = Xcodeproj::Project.open(xcodeproj_path)
  root_group = project.main_group.find_subpath(app_name, false) || project.main_group.new_group(app_name, app_name)
  groups = destination_relative_path.split('/')
  current_group = root_group

  groups.each do |group_name|
    current_group = current_group.find_subpath(group_name, false) || current_group.new_group(group_name, group_name)
  end

  Dir.glob("#{destination}/**/*").each do |item|
    next if File.extname(item) == ".gula"
    next if File.directory?(item)
    relative_path = item.sub("#{destination}/", "")
    path_components = relative_path.split("/")
    group = current_group

    path_components.each do |component|
      if File.extname(component).empty?
        group = group.find_subpath(component, false) || group.new_group(component, component)
      end
    end

    file_name = File.basename(item)
    existing_ref = group.files.find { |f| f.path == file_name }
    if !existing_ref
      file_ref = group.new_reference(file_name)
      project.targets.first.add_file_references([file_ref])
      puts "✅ Referencia añadida: #{file_name} en el grupo: #{group.name}"
    end
  end
  project.save
end

def copy_folder_integrated(origin_folder, destination_folder, folder_name)
  return unless Dir.exist?(origin_folder)

  puts "┌──────────────────────────────────────────"
  puts "│ 📁 Carpeta: #{folder_name}"
  puts "│ 📥 Origen: #{origin_folder}"
  puts "│ 📤 Destino: #{destination_folder}"

  FileUtils.mkdir_p(destination_folder)

  files_copied = 0
  Dir.glob("#{origin_folder}/**/*").each do |item|
    relative_path = item.sub("#{origin_folder}/", "")
    destination_path = File.join(destination_folder, relative_path)

    if File.directory?(item)
      FileUtils.mkdir_p(destination_path)
    else
      FileUtils.mkdir_p(File.dirname(destination_path))
      FileUtils.cp(item, destination_path)
      puts "│ ✅ #{relative_path}"
      files_copied += 1
    end
  end

  puts "│ Total archivos: #{files_copied}"
  puts "└──────────────────────────────────────────"
  puts ""

  files_copied
end

def create_groups_for_integrated(xcodeproj_path, app_name, base_destination, layer_name, module_name)
  project = Xcodeproj::Project.open(xcodeproj_path)
  root_group = project.main_group.find_subpath(app_name, false) || project.main_group.new_group(app_name, app_name)

  # Crear grupo para la capa (Data, Domain, etc.) - sin subcarpeta del módulo
  layer_group = root_group.find_subpath(layer_name, false) || root_group.new_group(layer_name, layer_name)

  destination = "#{base_destination}/#{layer_name}"

  return unless Dir.exist?(destination)

  Dir.glob("#{destination}/**/*").each do |item|
    next if File.extname(item) == ".gula"
    next if File.directory?(item)

    relative_path = item.sub("#{destination}/", "")
    path_components = relative_path.split("/")
    group = layer_group

    # Crear subgrupos según la estructura de directorios
    path_components[0..-2].each do |component|
      group = group.find_subpath(component, false) || group.new_group(component, component)
    end

    file_name = File.basename(item)
    existing_ref = group.files.find { |f| f.path == file_name }

    if !existing_ref
      file_ref = group.new_reference(file_name)
      project.targets.first.add_file_references([file_ref])
      puts "✅ Referencia añadida: #{file_name} en #{layer_name}/#{path_components[0..-2].join('/')}"
    end
  end

  project.save
end

def main
  xcode_version

  xcodeproj_path, app_name = find_xcode_project_and_app_name
  project_created_with_xcode = check_object_version(xcodeproj_path)

  module_origin = ARGV[0]      # Ruta del módulo en temp-gula
  module_name = ARGV[1]        # Nombre del módulo (Authentication)
  temporary_dir = ARGV[2]      # Directorio temporal

  base_destination = app_name  # Directorio base de la app

  puts ""
  puts "═══════════════════════════════════════════════"
  puts "🔀 MODO INTEGRACIÓN: Distribuyendo por capas"
  puts "═══════════════════════════════════════════════"
  puts "📦 Módulo: #{module_name}"
  puts "📂 Destino base: #{base_destination}"
  puts ""

  # Obtener todas las carpetas del módulo
  layers = Dir.glob("#{module_origin}/*/").map { |d| File.basename(d) }

  total_files = 0
  layers.each do |layer|
    origin_folder = "#{module_origin}/#{layer}"
    # Copiar directamente a la capa sin subcarpeta del módulo
    # Ej: Data/Datasource/... en lugar de Data/Authentication/Datasource/...
    destination_folder = "#{base_destination}/#{layer}"

    files = copy_folder_integrated(origin_folder, destination_folder, layer)
    total_files += files

    # Añadir a Xcode (solo para Xcode 15 o inferior)
    if project_created_with_xcode == 15
      puts "✅ Integrando #{layer} en proyecto Xcode..."
      create_groups_for_integrated(xcodeproj_path, app_name, base_destination, layer, module_name)
    end
  end

  puts ""
  puts "═══════════════════════════════════════════════"
  puts "✅ Integración completada"
  puts "   Total archivos copiados: #{total_files}"
  puts "   Capas procesadas: #{layers.join(', ')}"
  puts "═══════════════════════════════════════════════"
  puts ""

  # Procesar dependencias
  read_gula_file_and_install_dependencies(xcodeproj_path, app_name, module_origin, temporary_dir, project_created_with_xcode)
end

main
