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
  REQUESTED_MODULES=$1
  for MODULE_NAME in "${REQUESTED_MODULES[@]}"; do
    if ls ./dist/*"$MODULE_NAME"*.tar.gz 1> /dev/null 2>&1; then
      mv ./dist/*"$MODULE_NAME"*.tar.gz ./../$GULA_PACKAGES_DIR
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
