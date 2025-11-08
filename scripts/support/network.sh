#!/bin/bash

# Función para obtener el username desde la API key
get_username_from_api() {
  local API_KEY="$1"
  local response
  local username

  # Llamar al endpoint para obtener el username
  response=$(curl --location --silent --show-error --write-out "HTTPSTATUS:%{http_code}" \
    "https://services.rudo.es/api/gula/auth/resolve-username/$API_KEY" \
    --header "Content-Type: application/json" 2>/dev/null)

  local body=$(echo $response | sed -e 's/HTTPSTATUS\:.*//g')
  local http_status=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  # Si el endpoint funciona (HTTP 200) y devuelve un username válido
  if [ "$http_status" -eq 200 ]; then
    username=$(echo $body | jq -r '.username')

    # Si el username es válido, devolverlo
    if [ "$username" != "null" ] && [ -n "$username" ]; then
      echo "$username"
      return 0
    fi
  fi

  # Si falla, devolver "unknown"
  echo "unknown"
  return 1
}

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
  local apikey=${1:-}
  local platform=${2:-}

  # Validar que ambos parámetros estén presentes
  if [ -z "$apikey" ]; then
    echo -e "${RED}Error: No se proporcionó la KEY. Usa --key=tu_clave${NC}" >&2
    exit 1
  fi

  if [ -z "$platform" ]; then
    echo -e "${RED}Error interno: No se especificó la plataforma${NC}" >&2
    exit 1
  fi

  ACCESSTOKEN=$(get_bitbucket_access_token "$apikey" "$platform")
  if [ $? -eq 0 ]; then
    echo -e "✅ Obtención del código de acceso"
  else
    echo -e "${RED}Error: No se ha podido completar la validación KEY incorrecta.${NC}"
    exit 1
  fi
}

get_allowed_modules() {
  local API_KEY="$1"
  local tech="$2"
  local response

  # Mapear 'back' a 'python' para el microservicio
  local tech_name="$tech"
  if [ "$tech" = "back" ]; then
    tech_name="python"
  fi

  # Llamar al nuevo endpoint de módulos permitidos
  response=$(curl --location --silent --show-error --write-out "HTTPSTATUS:%{http_code}" \
    "https://services.rudo.es/api/gula/repositories/modules/allowed?api_key=${API_KEY}&tech=${tech_name}" \
    --header "Content-Type: application/json" 2>/dev/null)

  local body=$(echo $response | sed -e 's/HTTPSTATUS\:.*//g')
  local http_status=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  # Si el endpoint responde correctamente
  if [ "$http_status" -eq 200 ]; then
    local unrestricted=$(echo $body | jq -r '.unrestricted')

    # Si unrestricted es true, devolver señal especial
    if [ "$unrestricted" = "true" ]; then
      echo "UNRESTRICTED"
      return 0
    fi

    # Si unrestricted es false, devolver lista de módulos
    local modules=$(echo $body | jq -r '.modules[]' 2>/dev/null)
    if [ -n "$modules" ]; then
      echo "$modules"
      return 0
    else
      # No hay módulos permitidos
      echo "NO_MODULES_ALLOWED"
      return 1
    fi
  else
    # Si falla el endpoint, devolver señal para usar método antiguo
    echo "FALLBACK_TO_OLD_METHOD"
    return 2
  fi
}

check_version() {
  local cache_file="/tmp/gula_version_cache"
  local cache_duration=3600  # 1 hora en segundos
  local current_time=$(date +%s)
  local latest_tag=""

  # Verificar si existe caché y es válido
  if [ -f "$cache_file" ]; then
    local cache_time=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)
    local time_diff=$((current_time - cache_time))

    if [ $time_diff -lt $cache_duration ]; then
      # Usar caché
      latest_tag=$(cat "$cache_file")
    fi
  fi

  # Si no hay caché válido, consultar API
  if [ -z "$latest_tag" ]; then
    latest_tag=$(curl -s https://api.github.com/repos/rudoapps/homebrew-gula/releases/latest | jq -r '.tag_name')

    # Si la consulta fue exitosa (no es null ni vacío), guardar en caché
    if [ -n "$latest_tag" ] && [ "$latest_tag" != "null" ]; then
      echo "$latest_tag" > "$cache_file"
    else
      # Si falla por rate limit, asumir que está actualizado
      echo -e "✅ Tienes la versión más actual"
      echo ""
      return 0
    fi
  fi

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