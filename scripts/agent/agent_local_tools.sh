#!/bin/bash

# Agent Local Tools - Ejecuta herramientas localmente sobre el proyecto del usuario
# Este modulo permite al agente operar sobre archivos y comandos en la maquina del usuario

# Configuracion de limites de seguridad
MAX_FILE_SIZE=50000          # 50KB max por archivo
MAX_OUTPUT_LINES=200         # Maximo lineas de output
MAX_COMMAND_TIMEOUT=30       # Timeout para comandos en segundos
MAX_SEARCH_RESULTS=50        # Maximo resultados de busqueda

# Archivos sensibles que NO se pueden leer
BLOCKED_FILE_EXTENSIONS=".pem .key .p12 .pfx .keystore .jks .secret .credentials"
BLOCKED_FILE_NAMES=".env .env.local .env.production .env.development id_rsa id_ed25519 id_dsa authorized_keys known_hosts .netrc .npmrc .pypirc"

# Audit log
AUDIT_LOG_FILE="$HOME/.config/gula-agent/audit.log"

# Función de audit logging
audit_log() {
    local action="$1"
    local details="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$(dirname "$AUDIT_LOG_FILE")"
    echo "[$timestamp] $action: $details" >> "$AUDIT_LOG_FILE"
}

# ============================================================================
# GENERACION DE CONTEXTO DEL PROYECTO
# ============================================================================

# Detecta el tipo de proyecto basado en archivos presentes
detect_project_type() {
    if [ -f "pubspec.yaml" ]; then
        echo "flutter"
    elif [ -f "Package.swift" ] || ls *.xcodeproj 1> /dev/null 2>&1 || ls *.xcworkspace 1> /dev/null 2>&1; then
        echo "ios"
    elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
        echo "android"
    elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f "setup.py" ]; then
        echo "python"
    elif [ -f "package.json" ]; then
        echo "node"
    elif [ -f "Cargo.toml" ]; then
        echo "rust"
    elif [ -f "go.mod" ]; then
        echo "go"
    else
        echo "unknown"
    fi
}

# Genera arbol de archivos comprimido (excluye directorios comunes)
generate_file_tree() {
    local max_depth="${1:-4}"
    local max_files="${2:-100}"

    find . -maxdepth "$max_depth" -type f \
        -not -path "*/\.*" \
        -not -path "*/node_modules/*" \
        -not -path "*/__pycache__/*" \
        -not -path "*/venv/*" \
        -not -path "*/.venv/*" \
        -not -path "*/.git/*" \
        -not -path "*/build/*" \
        -not -path "*/dist/*" \
        -not -path "*/.build/*" \
        -not -path "*/Pods/*" \
        -not -path "*/.dart_tool/*" \
        -not -path "*/DerivedData/*" \
        -not -name "*.pyc" \
        -not -name "*.class" \
        -not -name "*.o" \
        -not -name "*.lock" \
        -not -name "package-lock.json" \
        -not -name "yarn.lock" \
        -not -name "Podfile.lock" \
        2>/dev/null | sort | head -"$max_files"
}

# Detecta archivos clave del proyecto
detect_key_files() {
    local key_files=()
    local candidates=(
        "README.md" "readme.md"
        "requirements.txt" "pyproject.toml" "setup.py"
        "package.json" "tsconfig.json"
        "pubspec.yaml"
        "build.gradle" "build.gradle.kts" "settings.gradle"
        "Package.swift" "Podfile"
        "Cargo.toml"
        "go.mod"
        "Makefile" "Dockerfile" "docker-compose.yml"
        ".env.example" "configuration.gula"
    )

    for f in "${candidates[@]}"; do
        if [ -f "$f" ]; then
            key_files+=("$f")
        fi
    done

    # Convertir a JSON array
    printf '%s\n' "${key_files[@]}" | python3 -c "import sys, json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))"
}

# Lee contenido de dependencias
get_dependencies_summary() {
    local project_type="$1"

    case "$project_type" in
        python)
            if [ -f "requirements.txt" ]; then
                head -30 requirements.txt
            elif [ -f "pyproject.toml" ]; then
                grep -A 50 "dependencies" pyproject.toml 2>/dev/null | head -30
            fi
            ;;
        node)
            if [ -f "package.json" ]; then
                python3 -c "
import json
try:
    pkg = json.load(open('package.json'))
    deps = list(pkg.get('dependencies', {}).keys())[:20]
    dev = list(pkg.get('devDependencies', {}).keys())[:10]
    print('deps:', ', '.join(deps))
    print('devDeps:', ', '.join(dev))
except: pass
"
            fi
            ;;
        flutter)
            if [ -f "pubspec.yaml" ]; then
                grep -A 30 "dependencies:" pubspec.yaml 2>/dev/null | head -30
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

# Genera contexto completo del proyecto como JSON
generate_project_context() {
    local project_type=$(detect_project_type)
    local project_name=$(basename "$PWD")
    local file_tree=$(generate_file_tree)
    local key_files=$(detect_key_files)
    local git_branch=$(git branch --show-current 2>/dev/null || echo "")
    local git_status=$(git status --short 2>/dev/null | head -20 || echo "")
    local dependencies=$(get_dependencies_summary "$project_type")

    # Read project rules file if exists (.claude-project, CLAUDE.md, or .agent-rules)
    local project_rules=""
    for rules_file in ".claude-project" "CLAUDE.md" ".agent-rules"; do
        if [ -f "$rules_file" ]; then
            project_rules=$(cat "$rules_file" 2>/dev/null | head -200)
            break
        fi
    done

    python3 << PYEOF
import json

context = {
    "project_type": "$project_type",
    "project_name": "$project_name",
    "root_path": "$PWD",
    "file_tree": """$file_tree""".strip(),
    "git_branch": "$git_branch",
    "git_status": """$git_status""".strip(),
    "key_files": $key_files,
    "dependencies": """$dependencies""".strip(),
    "project_rules": """$project_rules""".strip()
}

print(json.dumps(context))
PYEOF
}

# ============================================================================
# EJECUCION DE HERRAMIENTAS LOCALES
# ============================================================================

# Lee un archivo del proyecto
tool_read_file() {
    local input="$1"
    local path=$(echo "$input" | python3 -c "import sys, json; print(json.load(sys.stdin).get('path', ''))")

    # Validar que no salga del directorio actual (usando realpath para resolver symlinks)
    local path_check=$(python3 -c "
import os
path = '$path'
cwd = os.getcwd()
# Resolver ruta REAL (sigue symlinks) - protección contra symlink attacks
real_path = os.path.realpath(path)
# Verificar que esta dentro del directorio actual
if real_path.startswith(cwd + os.sep) or real_path == cwd:
    print('OK:' + real_path)
else:
    print('ERROR:Path fuera del proyecto (posible symlink): ' + real_path)
")

    if [[ "$path_check" == ERROR:* ]]; then
        audit_log "READ_BLOCKED" "Path fuera del proyecto: $path"
        echo "Error: ${path_check#ERROR:}"
        return 1
    fi

    # Usar la ruta resuelta
    local resolved_path="${path_check#OK:}"
    local filename=$(basename "$resolved_path")
    local extension=".${filename##*.}"

    # Verificar extensiones bloqueadas
    if [[ "$BLOCKED_FILE_EXTENSIONS" == *"$extension"* ]]; then
        audit_log "READ_BLOCKED" "Extensión bloqueada: $path ($extension)"
        echo "Error: No se permite leer archivos con extensión $extension (archivo sensible)"
        return 1
    fi

    # Verificar nombres de archivo bloqueados
    for blocked in $BLOCKED_FILE_NAMES; do
        if [[ "$filename" == "$blocked" ]]; then
            audit_log "READ_BLOCKED" "Archivo bloqueado: $path"
            echo "Error: No se permite leer $filename (archivo sensible de configuración)"
            return 1
        fi
    done

    if [ ! -f "$resolved_path" ]; then
        echo "Error: Archivo no encontrado: $path"
        return 1
    fi

    # Audit log de lectura exitosa
    audit_log "READ" "$path"

    # Verificar tamano
    local size=$(stat -f%z "$resolved_path" 2>/dev/null || stat -c%s "$resolved_path" 2>/dev/null)
    if [ "$size" -gt "$MAX_FILE_SIZE" ]; then
        echo "# Archivo truncado (${size} bytes, max: ${MAX_FILE_SIZE})"
        head -c "$MAX_FILE_SIZE" "$resolved_path"
        echo -e "\n... [truncado]"
    else
        cat "$resolved_path"
    fi
}

# Lista archivos en un directorio
tool_list_files() {
    local input="$1"
    local path=$(echo "$input" | python3 -c "import sys, json; print(json.load(sys.stdin).get('path', '.'))")
    local pattern=$(echo "$input" | python3 -c "import sys, json; print(json.load(sys.stdin).get('pattern', '*'))")

    # Validar que no salga del directorio actual (usando realpath para symlinks)
    local path_check=$(python3 -c "
import os
path = '$path'
cwd = os.getcwd()
real_path = os.path.realpath(path)
if real_path.startswith(cwd + os.sep) or real_path == cwd:
    print('OK:' + real_path)
else:
    print('ERROR:Path fuera del proyecto (posible symlink): ' + real_path)
")

    if [[ "$path_check" == ERROR:* ]]; then
        audit_log "LIST_BLOCKED" "Path fuera del proyecto: $path"
        echo "Error: ${path_check#ERROR:}"
        return 1
    fi

    local resolved_path="${path_check#OK:}"

    if [ ! -d "$resolved_path" ]; then
        echo "Error: Directorio no encontrado: $path"
        return 1
    fi

    audit_log "LIST" "$path (pattern: $pattern)"

    find "$resolved_path" -maxdepth 3 -name "$pattern" -type f \
        -not -path "*/\.*" \
        -not -path "*/node_modules/*" \
        -not -path "*/__pycache__/*" \
        2>/dev/null | head -"$MAX_SEARCH_RESULTS"
}

# Busca texto en el codigo
tool_search_code() {
    local input="$1"
    local query=$(echo "$input" | python3 -c "import sys, json; print(json.load(sys.stdin).get('query', ''))")
    local file_pattern=$(echo "$input" | python3 -c "import sys, json; print(json.load(sys.stdin).get('file_pattern', ''))")

    if [ -z "$query" ]; then
        echo "Error: Se requiere un query de busqueda"
        return 1
    fi

    audit_log "SEARCH" "query='$query' pattern='$file_pattern'"

    local grep_opts="-rn --color=never"

    if [ -n "$file_pattern" ]; then
        grep_opts="$grep_opts --include=$file_pattern"
    fi

    # Excluir directorios comunes
    grep $grep_opts \
        --exclude-dir=node_modules \
        --exclude-dir=__pycache__ \
        --exclude-dir=venv \
        --exclude-dir=.venv \
        --exclude-dir=.git \
        --exclude-dir=build \
        --exclude-dir=dist \
        --exclude-dir=Pods \
        "$query" . 2>/dev/null | head -"$MAX_SEARCH_RESULTS"
}

# Escribe contenido a un archivo
tool_write_file() {
    local input="$1"
    local path=$(echo "$input" | python3 -c "import sys, json; print(json.load(sys.stdin).get('path', ''))")
    local content=$(echo "$input" | python3 -c "import sys, json; print(json.load(sys.stdin).get('content', ''))")

    if [ -z "$path" ]; then
        echo "Error: Se requiere una ruta de archivo"
        return 1
    fi

    # Validar que no salga del directorio actual (usando realpath para symlinks)
    local path_check=$(python3 -c "
import os
path = '$path'
cwd = os.getcwd()
# Para archivos nuevos, resolver el directorio padre
parent = os.path.dirname(path) or '.'
if os.path.exists(path):
    real_path = os.path.realpath(path)
else:
    # Archivo nuevo: verificar que el directorio padre está en el proyecto
    real_parent = os.path.realpath(parent)
    real_path = os.path.join(real_parent, os.path.basename(path))
# Verificar que esta dentro del directorio actual
if real_path.startswith(cwd + os.sep) or real_path == cwd:
    print('OK:' + real_path)
else:
    print('ERROR:Path fuera del proyecto (posible symlink): ' + real_path)
")

    if [[ "$path_check" == ERROR:* ]]; then
        audit_log "WRITE_BLOCKED" "Path fuera del proyecto: $path"
        echo "Error: ${path_check#ERROR:}"
        return 1
    fi

    # Usar la ruta resuelta
    local resolved_path="${path_check#OK:}"

    # =========================================================================
    # ARCHIVOS SENSIBLES QUE REQUIEREN APROBACIÓN
    # =========================================================================
    local needs_approval=false
    local risk_reason=""
    local filename=$(basename "$path")

    # Patrones de archivos sensibles
    local sensitive_patterns=(
        ".env|Archivo de variables de entorno"
        ".env.local|Archivo de variables de entorno local"
        ".env.production|Archivo de variables de producción"
        "credentials|Archivo de credenciales"
        "secrets|Archivo de secretos"
        ".ssh|Configuración SSH"
        ".aws|Configuración AWS"
        ".gitignore|Configuración de Git ignore"
        ".gitattributes|Atributos de Git"
        "package.json|Configuración de Node.js"
        "Podfile|Dependencias de iOS"
        "Gemfile|Dependencias de Ruby"
        "requirements.txt|Dependencias de Python"
        "pyproject.toml|Configuración de Python"
        "Dockerfile|Configuración de Docker"
        "docker-compose|Configuración de Docker Compose"
        ".yml|Archivo YAML de configuración"
        ".yaml|Archivo YAML de configuración"
        "config.|Archivo de configuración"
        "settings.|Archivo de configuración"
    )

    for entry in "${sensitive_patterns[@]}"; do
        local pattern="${entry%%|*}"
        local reason="${entry#*|}"
        if [[ "$path" == *"$pattern"* ]] || [[ "$filename" == *"$pattern"* ]]; then
            needs_approval=true
            risk_reason="$reason"
            break
        fi
    done

    # Verificar si el archivo ya existe (sobrescritura)
    if [ -f "$resolved_path" ]; then
        if [ "$needs_approval" = false ]; then
            needs_approval=true
            risk_reason="Sobrescribir archivo existente"
        else
            risk_reason="$risk_reason + Sobrescribir existente"
        fi
    fi

    # Si requiere aprobación, preguntar al usuario
    if [ "$needs_approval" = true ]; then
        echo "" >&2
        echo -e "${DIM}┌─${NC} ${CYAN}Confirmar escritura${NC} ${DIM}───────────────────────────┐${NC}" >&2
        echo -e "${DIM}│${NC}" >&2
        echo -e "${DIM}│${NC}  ${BOLD}$path${NC}" >&2
        echo -e "${DIM}│${NC}  ${DIM}$risk_reason · ${#content} bytes${NC}" >&2
        echo -e "${DIM}│${NC}" >&2
        echo -e "${DIM}└────────────────────────────────────────────────┘${NC}" >&2
        echo "" >&2

        # Input de tecla simple
        local approval=""

        echo -e "  ${GREEN}[p]${NC} Permitir   ${RED}[c]${NC} Cancelar" >&2
        echo "" >&2
        echo -n "  › " >&2

        local key
        if read -n 1 key < /dev/tty 2>/dev/null; then
            echo "" >&2
            case "$key" in
                p|P) approval="Permitir" ;;
                *) approval="Cancelar" ;;
            esac
        else
            echo "" >&2
            echo -e "${RED}Error: No se pudo leer input${NC}" >&2
            approval="Cancelar"
        fi

        # SEGURIDAD: Solo permitir si explícitamente se aprueba
        if [[ "$approval" != "Permitir" ]]; then
            echo -e "${DIM}Escritura rechazada${NC}" >&2
            echo "[USUARIO_RECHAZÓ] El usuario ha decidido NO permitir esta escritura. No intentes escribir este archivo de nuevo. Pregunta al usuario qué quiere hacer."
            return 1
        fi

        echo -e "${GREEN}✓${NC} ${DIM}Escritura permitida${NC}" >&2
        echo "" >&2
    fi

    # Crear directorio si no existe
    local dir=$(dirname "$resolved_path")
    mkdir -p "$dir"

    # Capturar contenido anterior para mostrar diff
    local old_content=""
    local is_new_file=true
    if [ -f "$resolved_path" ]; then
        old_content=$(cat "$resolved_path")
        is_new_file=false
    fi

    # Escribir archivo
    echo "$content" > "$resolved_path"

    # Audit log
    if [ "$is_new_file" = true ]; then
        audit_log "WRITE_NEW" "$path (${#content} bytes)"
    else
        audit_log "WRITE_MODIFY" "$path (${#content} bytes)"
    fi

    # Mostrar diff si es modificación de archivo existente
    if [ "$is_new_file" = false ]; then
        echo "" >&2
        echo -e "${CYAN}╭─ Diff: ${BOLD}$path${NC}" >&2
        echo -e "${CYAN}│${NC}" >&2

        # Crear archivos temporales para diff
        local tmp_old=$(mktemp)
        local tmp_new=$(mktemp)
        echo "$old_content" > "$tmp_old"
        echo "$content" > "$tmp_new"

        # Generar diff con colores
        diff -u "$tmp_old" "$tmp_new" 2>/dev/null | tail -n +4 | while IFS= read -r line; do
            if [[ "$line" == +* ]]; then
                echo -e "${CYAN}│${NC} ${GREEN}$line${NC}" >&2
            elif [[ "$line" == -* ]]; then
                echo -e "${CYAN}│${NC} ${RED}$line${NC}" >&2
            elif [[ "$line" == @* ]]; then
                echo -e "${CYAN}│${NC} ${BLUE}$line${NC}" >&2
            else
                echo -e "${CYAN}│${NC} $line" >&2
            fi
        done

        rm -f "$tmp_old" "$tmp_new"

        echo -e "${CYAN}│${NC}" >&2
        echo -e "${CYAN}╰────────────────────────────────────────────────${NC}" >&2
        echo "" >&2
        echo "Archivo modificado: $path ($(wc -c < "$resolved_path" | tr -d ' ') bytes)"
    else
        echo "Archivo creado: $path ($(wc -c < "$resolved_path" | tr -d ' ') bytes)"
    fi
}

# Ejecuta un comando en terminal
tool_run_command() {
    local input="$1"
    local command=$(echo "$input" | python3 -c "import sys, json; print(json.load(sys.stdin).get('command', ''))")

    if [ -z "$command" ]; then
        echo "Error: Se requiere un comando"
        return 1
    fi

    # =========================================================================
    # WHITELIST DE COMANDOS PRE-APROBADOS POR EL USUARIO
    # =========================================================================
    local whitelist_file="$HOME/.config/gula-agent/allowed_commands.txt"
    local is_whitelisted=false

    if [ -f "$whitelist_file" ]; then
        while IFS= read -r pattern || [ -n "$pattern" ]; do
            # Ignorar líneas vacías y comentarios
            [[ -z "$pattern" || "$pattern" == \#* ]] && continue
            if [[ "$command" =~ $pattern ]]; then
                is_whitelisted=true
                break
            fi
        done < "$whitelist_file"
    fi

    # =========================================================================
    # COMANDOS SIEMPRE BLOQUEADOS (catastróficos, sin posibilidad de aprobar)
    # =========================================================================
    local blocked_patterns=(
        "rm -rf /"
        "rm -rf ~"
        "rm -rf \$HOME"
        "rm -rf /*"
        "mkfs"
        "> /dev/sd"
        "> /dev/nvme"
        "dd if=/dev/zero"
        "dd if=/dev/random"
        ":(){ :|:& };:"  # Fork bomb
        "chmod -R 777 /"
        "chown -R /"
        "curl.*|.*sh"
        "curl.*|.*bash"
        "wget.*|.*sh"
        "wget.*|.*bash"
        "/etc/passwd"
        "/etc/shadow"
        "~/.ssh/"
        "id_rsa"
        "id_ed25519"
        "ssh-keygen"
        "base64 -d.*|.*sh"
        "eval.*base64"
        "python.*-c.*import os"
        "nc -e"           # Netcat reverse shell
        "ncat -e"
        "/bin/sh -i"      # Interactive shell
        "bash -i"
        "0<&196"          # Bash reverse shell
        "exec 5<>"        # File descriptor manipulation
    )

    for pattern in "${blocked_patterns[@]}"; do
        if [[ "$command" == *"$pattern"* ]]; then
            audit_log "COMMAND_BLOCKED" "Patrón bloqueado: $pattern en: $command"
            echo "Error: Comando bloqueado permanentemente por seguridad: contiene '$pattern'"
            return 1
        fi
    done

    # =========================================================================
    # COMANDOS QUE REQUIEREN APROBACIÓN DEL USUARIO
    # =========================================================================
    local needs_approval=false
    local risk_reason=""

    # Patrones que requieren aprobación
    local approval_patterns=(
        "rm -rf|Eliminar recursivamente archivos"
        "rm -r|Eliminar recursivamente"
        "rm \\*|Eliminar con wildcard"
        "rm -f|Eliminar forzado"
        "sudo|Ejecutar como superusuario"
        "kill|Terminar proceso"
        "killall|Terminar todos los procesos"
        "pkill|Terminar procesos por nombre"
        "chmod|Cambiar permisos"
        "chown|Cambiar propietario"
        "mv /|Mover desde raíz"
        "cp -r /|Copiar desde raíz"
        "> |Sobrescribir archivo"
        ">>|Añadir a archivo"
        "curl.*-o|Descargar archivo"
        "wget|Descargar archivo"
        "npm install -g|Instalación global npm"
        "pip install|Instalar paquete Python"
        "brew install|Instalar con Homebrew"
        "apt install|Instalar con apt"
        "apt-get|Gestión de paquetes apt"
        "systemctl|Control de servicios"
        "service|Control de servicios"
        "shutdown|Apagar sistema"
        "reboot|Reiniciar sistema"
        "git push|Subir cambios a remoto"
        "git push -f|Push forzado"
        "git reset --hard|Reset destructivo"
        "docker rm|Eliminar contenedor"
        "docker rmi|Eliminar imagen"
        "docker system prune|Limpiar Docker"
    )

    for entry in "${approval_patterns[@]}"; do
        local pattern="${entry%%|*}"
        local reason="${entry#*|}"
        if [[ "$command" =~ $pattern ]]; then
            needs_approval=true
            risk_reason="$reason"
            break
        fi
    done

    # Si requiere aprobación, verificar whitelist o preguntar al usuario
    if [ "$needs_approval" = true ]; then
        if [ "$is_whitelisted" = true ]; then
            echo -e "${DIM}› auto-aprobado (whitelist)${NC}" >&2
        else
            echo "" >&2
            echo -e "${DIM}┌─${NC} ${CYAN}Confirmar ejecución${NC} ${DIM}───────────────────────────┐${NC}" >&2
            echo -e "${DIM}│${NC}" >&2
            echo -e "${DIM}│${NC}  ${MAGENTA}\$${NC} ${BOLD}$command${NC}" >&2
            echo -e "${DIM}│${NC}  ${DIM}$risk_reason${NC}" >&2
            echo -e "${DIM}│${NC}" >&2
            echo -e "${DIM}└────────────────────────────────────────────────┘${NC}" >&2
            echo "" >&2

            # Input de tecla simple (gum no funciona bien con subprocess)
            local approval=""

            echo -e "  ${GREEN}[e]${NC} Ejecutar   ${YELLOW}[s]${NC} Siempre   ${RED}[c]${NC} Cancelar" >&2
            echo "" >&2
            echo -n "  › " >&2

            local key
            if read -n 1 key < /dev/tty 2>/dev/null; then
                echo "" >&2
                case "$key" in
                    e|E) approval="Ejecutar" ;;
                    s|S) approval="Ejecutar siempre" ;;
                    *) approval="Cancelar" ;;
                esac
            else
                # Si falla la lectura, cancelar por seguridad
                echo "" >&2
                echo -e "${RED}Error: No se pudo leer input${NC}" >&2
                approval="Cancelar"
            fi

            # SEGURIDAD: Si approval está vacío o no es válido, SIEMPRE cancelar
            if [[ -z "$approval" ]] || [[ "$approval" == "Cancelar" ]]; then
                audit_log "COMMAND_REJECTED" "Usuario rechazó: $command"
                echo -e "${DIM}Comando rechazado${NC}" >&2
                # Mensaje claro para el agente (stdout)
                echo "[USUARIO_RECHAZÓ] El usuario ha decidido NO ejecutar este comando. No intentes ejecutarlo de nuevo. Pregunta al usuario qué quiere hacer."
                return 1
            elif [[ "$approval" == "Ejecutar siempre" ]]; then
                # Añadir patrón a whitelist
                mkdir -p "$(dirname "$whitelist_file")"
                local safe_pattern=$(echo "$command" | sed 's/[.[\*^$()+?{|]/\\&/g')
                echo "^${safe_pattern}$" >> "$whitelist_file"
                echo -e "${GREEN}✓${NC} ${DIM}Añadido a whitelist${NC}" >&2
            elif [[ "$approval" != "Ejecutar" ]]; then
                # Cualquier otro valor = cancelar
                echo -e "${DIM}Comando rechazado${NC}" >&2
                echo "[USUARIO_RECHAZÓ] El usuario ha decidido NO ejecutar este comando. No intentes ejecutarlo de nuevo. Pregunta al usuario qué quiere hacer."
                return 1
            fi

            echo -e "${GREEN}✓${NC} ${DIM}Ejecutando...${NC}" >&2
            echo "" >&2
        fi
    fi

    # =========================================================================
    # EJECUTAR COMANDO CON POSIBILIDAD DE CANCELACIÓN
    # =========================================================================

    # Audit log de ejecución
    audit_log "COMMAND_EXEC" "$command"

    # Mostrar hint de cancelación
    echo -e "${DIM}Ctrl+C para cancelar${NC}" >&2

    # Guardar el handler original de SIGINT
    local original_trap=$(trap -p SIGINT)

    # Variable para saber si fue cancelado
    local was_cancelled=false

    # Crear archivo temporal para el output
    local tmp_output=$(mktemp)

    # Ejecutar en background
    timeout "$MAX_COMMAND_TIMEOUT" bash -c "$command" > "$tmp_output" 2>&1 &
    local cmd_pid=$!

    # Handler para Ctrl+C - solo mata el comando, no el agente
    trap '
        was_cancelled=true
        kill $cmd_pid 2>/dev/null
        wait $cmd_pid 2>/dev/null
    ' SIGINT

    # Esperar a que termine el comando
    wait $cmd_pid 2>/dev/null
    local exit_code=$?

    # Restaurar el handler original
    eval "$original_trap"
    trap - SIGINT

    # Leer output
    local output=$(head -"$MAX_OUTPUT_LINES" "$tmp_output")
    rm -f "$tmp_output"

    # Mostrar resultado según el caso
    if [ "$was_cancelled" = true ]; then
        echo -e "\n${DIM}Comando cancelado${NC}"
        return 130  # Código estándar para SIGINT
    elif [ $exit_code -eq 124 ]; then
        echo "$output"
        echo -e "\n${YELLOW}Timeout (${MAX_COMMAND_TIMEOUT}s)${NC}"
    else
        echo "$output"
    fi

    return $exit_code
}

# Obtiene informacion de git
tool_git_info() {
    local input="$1"
    local info_type=$(echo "$input" | python3 -c "import sys, json; print(json.load(sys.stdin).get('type', 'status'))")

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: No es un repositorio git"
        return 1
    fi

    case "$info_type" in
        status)
            git status
            ;;
        log)
            git log --oneline -20
            ;;
        diff)
            git diff --stat
            ;;
        branch)
            git branch -a
            ;;
        *)
            echo "Tipo no soportado: $info_type (usa: status, log, diff, branch)"
            ;;
    esac
}

# Dispatcher principal de herramientas
execute_tool_locally() {
    local tool_name="$1"
    local tool_input="$2"

    case "$tool_name" in
        read_file)
            tool_read_file "$tool_input"
            ;;
        list_files)
            tool_list_files "$tool_input"
            ;;
        search_code)
            tool_search_code "$tool_input"
            ;;
        write_file)
            tool_write_file "$tool_input"
            ;;
        run_command)
            tool_run_command "$tool_input"
            ;;
        git_info)
            tool_git_info "$tool_input"
            ;;
        *)
            echo "Error: Tool desconocido: $tool_name"
            return 1
            ;;
    esac
}

# ============================================================================
# UTILIDADES
# ============================================================================

# Muestra informacion del proyecto actual
show_project_info() {
    local project_type=$(detect_project_type)
    local project_name=$(basename "$PWD")
    local file_count=$(generate_file_tree | wc -l | tr -d ' ')
    local git_branch=$(git branch --show-current 2>/dev/null || echo "N/A")

    echo -e "${BOLD}Proyecto: ${GREEN}$project_name${NC}"
    echo -e "Tipo: ${YELLOW}$project_type${NC}"
    echo -e "Archivos: ${YELLOW}$file_count${NC}"
    echo -e "Branch: ${YELLOW}$git_branch${NC}"
    echo -e "Ruta: ${YELLOW}$PWD${NC}"
}
