#!/bin/bash

clone() {
  # Clonar el repositorio específico desde Bitbucket en un directorio temporal
  remove_temporary_dir
  local repository=$1
  git clone "$repository" --single-branch --depth 1 "${TEMPORARY_DIR}"
  if [ $? -eq 0 ]; then
      echo -e "✅ Clonado correctamente en el directorio temporal"
  else
    echo -e "${RED}Se ha producido un error descargando el repositorio.${NC}"
    exit 1
  fi 
}

deep_clone() {
  # Clonar el repositorio específico desde Bitbucket en un directorio temporal
  remove_temporary_dir
  local repository=$1
  git clone "$repository" --branch main --single-branch "${TEMPORARY_DIR}"
  if [ $? -eq 0 ]; then
      echo -e "✅ Clonado correctamente en el directorio temporal"
  else
    echo -e "${RED}Se ha producido un error descargando el repositorio.${NC}"
    exit 1
  fi
}
