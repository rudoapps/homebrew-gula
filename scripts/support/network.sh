#!/bin/bash

get_bitbucket_access_token() {
  local API_KEY="$1"
  local tech="$2"
  local response
  local token

  response=$(curl --location --silent --show-error --write-out "HTTPSTATUS:%{http_code}" "https://dashboard.rudo.es/bitbucket_access/token/?platform=${tech}" --header "API-KEY: $API_KEY")

  local body=$(echo $response | sed -e 's/HTTPSTATUS\:.*//g')
  local http_status=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
  if [ "$http_status" -eq 200 ]; then
    token=$(echo $body | jq -r '.token')    
    echo "$token"
  else
    exit 1
  fi
}

get_access_token() {
  local apikey=$1
  local platform=$2
  ACCESSTOKEN=$(get_bitbucket_access_token $apikey $platform)
  if [ $? -eq 0 ]; then
    echo -e "✅ Obtención del código de acceso"
  else
    echo -e "${RED}Error: No se ha podido completar la validación KEY incorrecta.${NC}"
    exit 1
  fi
}

check_version() {
  latest_tag=$(curl -s https://api.github.com/repos/rudoapps/homebrew-gula/releases/latest | jq -r '.tag_name')
  if [ "$latest_tag" == "$VERSION" ]; then
    echo -e "✅ Tienes la versión más actual"
  else
    echo -e "Es necesario actualizar el script tu versión: $VERSION es antigua"
    brew update
    brew upgrade gula
    echo ""
    echo -e "✅ Script actualizado. Lanza el script de nuevo"
    echo -e "${BOLD}-----------------------------------------------${NC}"
    exit 1
  fi
  echo ""
}