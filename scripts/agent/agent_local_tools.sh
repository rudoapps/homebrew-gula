#!/bin/bash

# Agent Local Tools - Ejecuta herramientas localmente sobre el proyecto del usuario
# Este modulo permite al agente operar sobre archivos y comandos en la maquina del usuario

# Configuracion de limites de seguridad
MAX_FILE_SIZE=50000          # 50KB max por archivo
MAX_OUTPUT_LINES=200         # Maximo lineas de output
MAX_COMMAND_TIMEOUT=30       # Timeout para comandos en segundos
MAX_SEARCH_RESULTS=50        # Maximo resultados de busqueda

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
    "dependencies": """$dependencies""".strip()
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

    # Validar que no salga del directorio actual (usando Python para compatibilidad)
    local path_check=$(python3 -c "
import os
path = '$path'
cwd = os.getcwd()
# Resolver ruta absoluta
abs_path = os.path.abspath(path)
# Verificar que esta dentro del directorio actual
if abs_path.startswith(cwd + os.sep) or abs_path == cwd:
    print('OK:' + abs_path)
else:
    print('ERROR:Path fuera del proyecto: ' + abs_path)
")

    if [[ "$path_check" == ERROR:* ]]; then
        echo "Error: ${path_check#ERROR:}"
        return 1
    fi

    # Usar la ruta resuelta
    local resolved_path="${path_check#OK:}"

    if [ ! -f "$resolved_path" ]; then
        echo "Error: Archivo no encontrado: $path"
        return 1
    fi

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

    # Validar que no salga del directorio actual
    local path_check=$(python3 -c "
import os
path = '$path'
cwd = os.getcwd()
abs_path = os.path.abspath(path)
if abs_path.startswith(cwd + os.sep) or abs_path == cwd:
    print('OK:' + abs_path)
else:
    print('ERROR:Path fuera del proyecto: ' + abs_path)
")

    if [[ "$path_check" == ERROR:* ]]; then
        echo "Error: ${path_check#ERROR:}"
        return 1
    fi

    local resolved_path="${path_check#OK:}"

    if [ ! -d "$resolved_path" ]; then
        echo "Error: Directorio no encontrado: $path"
        return 1
    fi

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

    # Validar que no salga del directorio actual (usando Python para compatibilidad)
    local path_check=$(python3 -c "
import os
path = '$path'
cwd = os.getcwd()
# Resolver ruta absoluta
abs_path = os.path.abspath(path)
# Verificar que esta dentro del directorio actual
if abs_path.startswith(cwd + os.sep) or abs_path == cwd:
    print('OK:' + abs_path)
else:
    print('ERROR:Path fuera del proyecto: ' + abs_path)
")

    if [[ "$path_check" == ERROR:* ]]; then
        echo "Error: ${path_check#ERROR:}"
        return 1
    fi

    # Usar la ruta resuelta
    local resolved_path="${path_check#OK:}"

    # Crear directorio si no existe
    local dir=$(dirname "$resolved_path")
    mkdir -p "$dir"

    # Escribir archivo
    echo "$content" > "$resolved_path"
    echo "Archivo escrito: $path ($(wc -c < "$resolved_path") bytes)"
}

# Ejecuta un comando en terminal
tool_run_command() {
    local input="$1"
    local command=$(echo "$input" | python3 -c "import sys, json; print(json.load(sys.stdin).get('command', ''))")

    if [ -z "$command" ]; then
        echo "Error: Se requiere un comando"
        return 1
    fi

    # Lista de comandos peligrosos bloqueados
    local dangerous_patterns=("rm -rf /" "rm -rf ~" "sudo rm" "mkfs" "> /dev" "dd if=")
    for pattern in "${dangerous_patterns[@]}"; do
        if [[ "$command" == *"$pattern"* ]]; then
            echo "Error: Comando bloqueado por seguridad"
            return 1
        fi
    done

    # Ejecutar con timeout
    timeout "$MAX_COMMAND_TIMEOUT" bash -c "$command" 2>&1 | head -"$MAX_OUTPUT_LINES"
    local exit_code=$?

    if [ $exit_code -eq 124 ]; then
        echo -e "\n[Comando timeout despues de ${MAX_COMMAND_TIMEOUT}s]"
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
