#!/bin/bash

GULA_PACKAGES_DIR=gula_packages


create_gula_packages_dir() {
  if [ ! -d "gula_packages" ]; then \
	  mkdir -p $GULA_PACKAGES_DIR; \
  fi;
}

build_packages() {
  cd "$TEMPORARY_DIR" || return 1
  make build_packages
}

copy_packages() {
  REQUESTED_MODULES=("$@")
  for MODULE_NAME in "${REQUESTED_MODULES[@]}"; do
    echo $(pwd)
    matches=$(find ./"$TEMPORARY_DIR"/dist -type f -name "*.tar.gz" | grep "$MODULE_NAME")
    if [ -n "$matches" ]; then
      mv "$matches" ./../$GULA_PACKAGES_DIR
      echo "Archivo para el paquete $MODULE_NAME copiado correctamente en $GULA_PACKAGES_DIR"
    else
      echo "Archivo no encontrado para el paquete: $MODULE_NAME"
    fi
  done
  cd ..
}

install_packages() {
  poetry add ./$GULA_PACKAGES_DIR/*
}

install_python_dependencies() {
  poetry add build wheel setuptools
}
