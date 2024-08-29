#!/bin/bash

install_ios_module() {
  echo -e "${RED}Pendiente de terminar.${NC}"
  exit 0  
}

list_ios() {
  clone "https://x-token-auth:$KEY@bitbucket.org/rudoapps/gula-ios.git"
  DIRECTORY_PATH="${TEMPORARY_DIR}/${MODULES_PATH_IOS}"
  echo -e "${GREEN}Lista de módulos disponibles:"
  ls -l "$DIRECTORY_PATH" | grep '^d' | awk '{print $9}'
  echo -e "${NC}"
  remove_temporary_dir
}