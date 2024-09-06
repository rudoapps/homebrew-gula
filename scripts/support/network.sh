#!/bin/bash

get_bitbucket_access_token() {
  local API_KEY="$1"
  local tech="$2"
  local response
  local token

  # Ejecuta curl para obtener la respuesta
  response=$(curl --location --silent --show-error --write-out "HTTPSTATUS:%{http_code}" "https://dashboard.rudo.es/bitbucket_access/token/?platform=${tech}" --header "API-KEY: $API_KEY")

  # Separa el cuerpo de la respuesta del código de estado
  local body=$(echo $response | sed -e 's/HTTPSTATUS\:.*//g')
  local http_status=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  # Verifica si el código de estado es 200 (OK)
  if [ "$http_status" -eq 200 ]; then
    # Extrae el token del cuerpo de la respuesta
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