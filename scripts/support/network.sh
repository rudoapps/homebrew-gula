#!/bin/bash

# Función para obtener el username desde la API key
get_username_from_api() {
  local API_KEY="$1"
  local response
  local username

  # Llamar al endpoint para obtener el username (sin autenticación)
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
    if [ "$JSON_OUTPUT" != "true" ]; then
      echo -e "✅ Obtención del código de acceso"
    fi
  else
    if [ "$JSON_OUTPUT" = "true" ]; then
      echo "{\"status\":\"error\",\"message\":\"KEY incorrecta o inválida\"}"
    else
      echo -e "${RED}Error: No se ha podido completar la validación KEY incorrecta.${NC}"
    fi
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

# Compara dos versiones semánticas. Retorna:
# 0 = iguales, 1 = v1 > v2, 2 = v1 < v2
version_compare() {
  local v1="$1" v2="$2"

  # Eliminar prefijo 'v' si existe
  v1="${v1#v}"
  v2="${v2#v}"

  if [ "$v1" == "$v2" ]; then
    return 0
  fi

  # Comparar usando sort -V
  local smaller=$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -n1)
  if [ "$smaller" == "$v1" ]; then
    return 2  # v1 < v2
  else
    return 1  # v1 > v2
  fi
}

check_version() {
  local cache_file="/tmp/gula_version_cache"
  local cache_duration=3600  # 1 hora en segundos
  local current_time=$(date +%s)
  local latest_tag=""
  local using_cache=false

  # Verificar si existe caché y es válido
  if [ -f "$cache_file" ]; then
    local cache_time=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)
    local time_diff=$((current_time - cache_time))

    if [ $time_diff -lt $cache_duration ]; then
      # Usar caché
      latest_tag=$(cat "$cache_file")
      using_cache=true
    fi
  fi

  # Si no hay caché válido, consultar API con timeout
  if [ -z "$latest_tag" ]; then
    latest_tag=$(curl -s --max-time 3 https://api.github.com/repos/rudoapps/homebrew-gula/releases/latest 2>/dev/null | jq -r '.tag_name' 2>/dev/null)

    # Si la consulta fue exitosa (no es null ni vacío), guardar en caché
    if [ -n "$latest_tag" ] && [ "$latest_tag" != "null" ]; then
      echo "$latest_tag" > "$cache_file"
    else
      # Si falla la consulta, indicarlo y continuar
      echo -e "${YELLOW}⚠️  No se pudo verificar actualizaciones (versión actual: $VERSION)${NC}"
      echo ""
      return 0
    fi
  fi

  # Comparar versiones (capturar resultado para evitar exit con set -e)
  local cmp_result
  cmp_result=$(version_compare "$VERSION" "$latest_tag"; echo $?)

  if [ "$cmp_result" -eq 0 ]; then
    # Versiones iguales
    if [ "$using_cache" = true ]; then
      echo -e "✅ Versión $VERSION (última verificada)"
    else
      echo -e "✅ Versión $VERSION (actualizada)"
    fi
  elif [ "$cmp_result" -eq 1 ]; then
    # Versión local es más nueva (desarrollo)
    echo -e "✅ Versión $VERSION (desarrollo)"
  else
    # Versión remota es más nueva - actualizar automáticamente
    echo -e "${YELLOW}📦 Nueva versión disponible: $latest_tag (actual: $VERSION)${NC}"
    echo -e "${CYAN}Actualizando automáticamente...${NC}"
    echo ""

    if brew update && brew upgrade gula; then
      echo ""
      echo -e "${GREEN}✅ Actualizado a $latest_tag${NC}"
      # Limpiar caché
      rm -f "$cache_file"
    else
      echo -e "${RED}❌ Error al actualizar. Intenta manualmente: brew update && brew upgrade gula${NC}"
    fi
  fi
  echo ""
}