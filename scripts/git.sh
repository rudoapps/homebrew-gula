#!/bin/bash

clone() {
  remove_temporary_dir
  # Clonar el repositorio específico desde Bitbucket en un directorio temporal
  local repository=$1
  git clone "$repository" --branch main --single-branch --depth 1 "${TEMPORARY_DIR}"
  if [ $? -eq 0 ]; then
      echo -e "${GREEN}OK.${NC}"
  else
    echo -e "${RED}Se ha producido un error descargando el repositorio.${NC}"
    exit 1
  fi 
}