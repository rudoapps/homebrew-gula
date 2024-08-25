#!/bin/bash

# Variables
DESTINATION_PROJECT_PATH="/ruta/al/proyecto/destino"
BITBUCKET_REPO_URL="https://{username}:{token}@bitbucket.org/{workspace}/{repo}.git"

# Verifica que se haya pasado el comando "install" y un nombre de módulo
if [ "$1" != "install" ] || [ -z "$2" ]; then
  echo "Uso: gula install {nombre-del-modulo}"
  exit 1
fi

MODULE_NAME="$2"

# Ruta del módulo en el proyecto destino
MODULE_PATH="$DESTINATION_PROJECT_PATH/$MODULE_NAME"

# Verificar si el módulo ya está instalado en el proyecto destino
if [ -d "$MODULE_PATH" ]; then
  echo "El módulo $MODULE_NAME ya existe en el proyecto destino."
  read -p "¿Deseas actualizar el módulo existente? (s/n): " CONFIRM
  if [ "$CONFIRM" != "s" ]; then
    echo "Instalación del módulo cancelada."
    exit 0
  fi
  # Eliminar el módulo existente antes de actualizarlo
  rm -rf "$MODULE_PATH"
fi

# Clonar el repositorio específico desde Bitbucket en un directorio temporal
git clone "$BITBUCKET_REPO_URL" --branch master --single-branch --depth 1 "$MODULE_NAME-temp"

# Verificar que el módulo existe en el repositorio clonado
if [ ! -d "$MODULE_NAME-temp/$MODULE_NAME" ]; then
  echo "Error: El módulo $MODULE_NAME no existe en el repositorio."
  rm -rf "$MODULE_NAME-temp"
  exit 1
fi

# Copiar el módulo al proyecto destino
cp -R "$MODULE_NAME-temp/$MODULE_NAME" "$DESTINATION_PROJECT_PATH/"

# Verificar si existe el archivo de dependencias en el módulo
DEPENDENCIES_FILE="$MODULE_NAME-temp/$MODULE_NAME/module_dependencies.gradle"
if [ -f "$DEPENDENCIES_FILE" ]; then
  echo "Validando y agregando dependencias del módulo al build.gradle del proyecto destino..."
  # Leer el archivo de dependencias
  while read -r line; do
    # Solo agregar líneas de dependencias (ignorando las líneas que no comienzan con 'implementation', 'api', etc.)
    if [[ $line =~ ^(implementation|api|compile|runtimeOnly|testImplementation|androidTestImplementation) ]]; then
      # Verificar si la dependencia ya existe en el build.gradle del proyecto destino
      if ! grep -q "$line" "$DESTINATION_PROJECT_PATH/build.gradle"; then
        # Si no existe, agregarla
        echo "$line" >> "$DESTINATION_PROJECT_PATH/build.gradle"
      else
        echo "Dependencia '$line' ya existe en el build.gradle, no se agregó nuevamente."
      fi
    fi
  done < "$DEPENDENCIES_FILE"
fi

# Eliminar el repositorio temporal
rm -rf "$MODULE_NAME-temp"

# Modificar el archivo settings.gradle del proyecto destino
if ! grep -q "include ':$MODULE_NAME'" "$DESTINATION_PROJECT_PATH/settings.gradle"; then
  echo "include ':$MODULE_NAME'" >> "$DESTINATION_PROJECT_PATH/settings.gradle"
else
  echo "El módulo $MODULE_NAME ya estaba incluido en settings.gradle."
fi

echo "Módulo $MODULE_NAME copiado y configurado correctamente en el proyecto destino. Repositorio temporal eliminado."
