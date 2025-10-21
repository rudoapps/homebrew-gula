#!/bin/bash

get_bitbucket_access_token() {
  local API_KEY="$1"
  local tech="$2"
  local response
  local token

  # ============================================
  # INTENTAR NUEVO ENDPOINT (Microservicio Gula)
  # ============================================

  # Determinar el comando basado en GULA_COMMAND
  local command=""
  case "$GULA_COMMAND" in
    "list") command="list" ;;
    "install") command="install" ;;
    "create") command="create" ;;
    "branches") command="branches" ;;
    *) command="install" ;;  # default fallback
  esac

  # Mapear 'back' a 'python' para el microservicio
  local tech_name="$tech"
  if [ "$tech" = "back" ]; then
    tech_name="python"
  fi

  # Intentar nuevo endpoint
  response=$(curl --location --silent --show-error --write-out "HTTPSTATUS:%{http_code}" \
    "https://services.rudo.es/api/gula/repositories/resolve-token" \
    --header "Content-Type: application/json" \
    --data "{\"api_key\":\"$API_KEY\",\"command\":\"$command\",\"tech\":\"$tech_name\"}" 2>/dev/null)

  local body=$(echo $response | sed -e 's/HTTPSTATUS\:.*//g')
  local http_status=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  # Si el nuevo endpoint funciona (HTTP 200) y devuelve un token válido
  if [ "$http_status" -eq 200 ]; then
    token=$(echo $body | jq -r '.token')

    # Si el token es válido, usarlo
    if [ "$token" != "null" ] && [ -n "$token" ]; then
      echo "$token"
      return 0
    fi
  fi

  # ============================================
  # FALLBACK: INTENTAR ENDPOINT ANTIGUO
  # ============================================

  echo -e "${YELLOW}⚠️  Usando sistema de autenticación legacy...${NC}" >&2

  response=$(curl --location --silent --show-error --write-out "HTTPSTATUS:%{http_code}" \
    "https://dashboard.rudo.es/bitbucket_access/token/?platform=${tech}" \
    --header "API-KEY: $API_KEY" 2>/dev/null)

  local body=$(echo $response | sed -e 's/HTTPSTATUS\:.*//g')
  local http_status=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  if [ "$http_status" -eq 200 ]; then
    token=$(echo $body | jq -r '.token')
    echo "$token"
    return 0
  else
    # Ambos endpoints fallaron
    echo -e "${RED}❌ Error: KEY incorrecta o no autorizada (HTTP: $http_status)${NC}" >&2
    echo -e "${RED}   Verifica que tu KEY sea válida y tenga permisos para '$command' en '$tech_name'${NC}" >&2
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