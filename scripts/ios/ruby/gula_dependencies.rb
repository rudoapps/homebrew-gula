#!/usr/bin/env ruby

def read_gula_file(folder_path, prefix)
  gula_file = Dir.glob("#{folder_path}/*.gula").first
  
  if gula_file.nil?
    puts "❌ No se encontró ningún archivo .gula en la carpeta '#{folder_path}'."
  else
    items_to_copy = File.readlines(gula_file).map(&:strip).reject(&:empty?).select { |item| item.start_with?(prefix) }
    
    if items_to_copy.empty?
      puts "⚠️ No se encontraron elementos que comiencen con '#{prefix}' en #{gula_file}."
    end

    items_to_copy 
  end
end