#!/usr/bin/env ruby

require 'xcodeproj'
require 'fileutils'

# Función para encontrar el proyecto Xcode y extraer el nombre de la aplicación
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

# Función para encontrar o crear un grupo en el proyecto Xcode
def find_or_create_group(group, group_name, folder_path = nil)
  existing_group = group.groups.find { |g| g.display_name == group_name }
  
  if existing_group
    puts "🚫 Grupo '#{group_name}' ya existe en el proyecto."
    return existing_group
  else
    puts "✅ Creando grupo '#{group_name}' en el proyecto y carpeta en '#{folder_path}'."
    FileUtils.mkdir_p(folder_path) if folder_path # Crear la carpeta en el sistema de archivos si es necesario
    return group.new_group(group_name, folder_path)
  end
end

# Función para encontrar el grupo de la aplicación dentro del proyecto Xcode
def find_app_group(project, app_name)
  project.main_group.groups.each do |group|
    return group if group.display_name == app_name
  end
  puts "❌ No se encontró el grupo de la aplicación con el nombre '#{app_name}' en el proyecto."
  exit 1
end

# Función para copiar y añadir una carpeta al proyecto Xcode, preservando la estructura de directorios
def copy_and_add_folder_to_project(project_path, folder_path, app_name, destination_group_name)
  project = Xcodeproj::Project.open(project_path)
  
  # Encontrar el grupo de la aplicación
  app_group = find_app_group(project, app_name)
  destination_group = find_or_create_group(app_group, destination_group_name)
  
  # Función recursiva para copiar y añadir archivos y carpetas al proyecto
  def copy_and_add_files_recursively(group, folder_path, destination_path)
    Dir.entries(folder_path).each do |entry|
      next if entry == '.' || entry == '..'
      
      full_path = File.join(folder_path, entry)
      dest_path = File.join(destination_path, entry)
      
      if File.extname(full_path) == ".gula"
        puts "❌ Ignorando archivo .gula: #{entry}"
        next
      end
      
      if File.directory?(full_path)
        puts "📁 Procesando directorio: #{entry}"
        FileUtils.mkdir_p(dest_path)  # Crear el directorio en la carpeta de destino
        new_group = find_or_create_group(group, entry, dest_path)
        copy_and_add_files_recursively(new_group, full_path, dest_path)
      elsif File.file?(full_path)
        puts "📄 Copiando archivo: #{entry} a #{dest_path}"
        FileUtils.cp(full_path, dest_path)  # Copiar el archivo a la carpeta de destino
        group.new_reference(dest_path)
      end
    end
  end

  # Definir la carpeta de destino como la carpeta que tiene el nombre del proyecto
  project_base_path = File.dirname(project_path)
  destination_folder = File.join(project_base_path, app_name, destination_group_name)
  
  FileUtils.mkdir_p(destination_folder)  # Crear la carpeta de destino si no existe
  main_group = find_or_create_group(destination_group, File.basename(folder_path), destination_folder)
  copy_and_add_files_recursively(main_group, folder_path, destination_folder)

  project.save
end

# Función para leer el archivo .gula y obtener los elementos a copiar
def read_gula_file(folder_path, prefix)
  gula_file = Dir.glob("#{folder_path}/*.gula").first
  
  if gula_file.nil?
    puts "❌ No se encontró ningún archivo .gula en la carpeta '#{folder_path}'."
    exit 1
  end

  items_to_copy = File.readlines(gula_file).map(&:strip).reject(&:empty?).select { |item| item.start_with?(prefix) }
  
  if items_to_copy.empty?
    puts "⚠️ No se encontraron elementos que comiencen con '#{prefix}' en #{gula_file}."
  end

  items_to_copy
end

# Función principal
def main
  temp_folder = ARGV[0]
  folder_path = "#{temp_folder}/#{ARGV[1]}"

  if folder_path.nil? || !Dir.exist?(folder_path)
    puts "❌ Debe proporcionar una carpeta válida."
    exit 1
  end

  xcode_project_path, app_name = find_xcode_project_and_app_name
  
  copy_and_add_folder_to_project(xcode_project_path, folder_path, app_name, "Modules")
  items_to_copy = read_gula_file(folder_path, "Gula")

  if items_to_copy.size > 0
    puts "----------------------------------------------------"
    puts "🏗️ Elementos a copiar en Shared"
    items_to_copy.each do |item|
      puts "📦 #{item}"  
    end
    puts "----------------------------------------------------"
    for item in items_to_copy do
      copy_and_add_folder_to_project(xcode_project_path, "#{temp_folder}/#{item}", app_name, "Shared")
    end
  end

  items_to_copy = read_gula_file(folder_path, "Library")
  if items_to_copy.size > 0
    puts "----------------------------------------------------"
    puts ""
    puts "❗❗❗ Tendrás que instalar manualmente estos package ❗❗❗"
    puts ""
    items_to_copy.each do |item|
      puts "📦 #{item.gsub('Library/', '')}"  
    end
    puts ""
    puts "----------------------------------------------------"
    puts "Carpeta '#{folder_path}' y su estructura añadidas correctamente al proyecto Xcode."
  end
end

# Ejecutar la función principal
main
