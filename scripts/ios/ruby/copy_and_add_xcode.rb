#!/usr/bin/env ruby

require 'xcodeproj'
require 'fileutils'
require_relative 'gula_dependencies.rb'

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

def copy_file(origin, destination)
  FileUtils.mkdir_p(destination)
  Dir.glob("#{origin}/**/*").each do |item|
    relative_path = item.sub("#{origin}/", "")
    destination_path = File.join(destination, relative_path)
    if File.directory?(item)
      FileUtils.mkdir_p(destination_path)
    else
      if File.exist?(destination_path)
        puts "❕ El archivo ya existe, omitiendo: #{destination_path}"
      else
        FileUtils.mkdir_p(File.dirname(destination_path))
        FileUtils.cp(item, destination_path)
      end
    end
  end
end

def copy_all_files(origin, destination)
  FileUtils.mkdir_p(destination)
  Dir.glob("#{origin}/**/*").each do |item|
    relative_path = item.sub("#{origin}/", "")
    destination_path = File.join(destination, relative_path)
    if File.directory?(item)
      FileUtils.mkdir_p(destination_path)
    else
      if File.exist?(destination_path)
        puts "❕ El archivo ya existe, omitiendo: #{destination_path}"
      else
        FileUtils.mkdir_p(File.dirname(destination_path))
        FileUtils.cp(item, destination_path)
      end
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
    
    #if !File.directory?(item)
      existing_ref = group.files.find { |f| f.path == file_name }
      if existing_ref
        puts "❕ El archivo ya forma parte del xcodeproj, omitiendo: #{file_name}"
      else
        file_ref = group.new_reference(file_name)
        project.targets.first.add_file_references([file_ref])
        puts "✅ Archivo añadido: #{file_name} en el grupo: #{group.name}"
      end
    #end
  end
  project.save
end

def copy_and_add_shared(xcodeproj_path, app_name, origin, temporary_dir)
  items_to_copy = read_gula_file(origin, "Gula")
  if items_to_copy.size > 0
    puts "----------------------------------------------------"
    puts "🏗️ Elementos a copiar en Shared"
    items_to_copy.each do |item|
      puts "📦 #{item}"  
    end
    puts "----------------------------------------------------"
    for item in items_to_copy do
      puts "Copiar #{item} a #{item.sub("Gula", app_name)}"
      copy_file("#{temporary_dir}/#{item}", item.sub("Gula", app_name))
    end
    create_groups(xcodeproj_path, app_name, "#{app_name}/Shared", "Shared")
  end
end

def notify_libraries(origin)
  items_to_copy = read_gula_file(origin, "Library")
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
  end
end

def main 
  xcodeproj_path, app_name = find_xcode_project_and_app_name

  origin = ARGV[0]
  destination_relative_path = ARGV[1]
  temporary_dir = ARGV[2]
  destination = "#{app_name}/#{destination_relative_path}"
  puts "✅ Copiando desde #{origin} hacia #{destination}"
  copy_all_files(origin, destination)

  puts "✅ Archivos copiados exitosamente de #{origin} a #{destination}"

  puts "✅ Integrando en el proyecto Xcode: #{xcodeproj_path}"
  create_groups(xcodeproj_path, app_name, destination, destination_relative_path)
  
  puts "✅ Archivos integrados exitosamente en el proyecto Xcode dentro de #{destination_relative_path}"

  copy_and_add_shared(xcodeproj_path, app_name, origin, temporary_dir)
  notify_libraries(origin)
end
main
