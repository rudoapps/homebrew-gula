#!/bin/bash

python_install_all_templates() {
    # Validar entrada
    if [ -z "$1" ]; then
        echo "Error: Debes proporcionar un nombre para el módulo o caso de uso."
        echo "Uso: gula template <ModuleName> [--type=fastapi|django]"
        exit 1
    fi

    local TEMPLATE_NAME=$1
    local TEMPLATE_TYPE=${TEMPLATE_TYPE:-fastapi}
    
    PROJECT_DIR=$(pwd)
    echo ""
    echo "Generando templates para Python ($TEMPLATE_TYPE) en: $PROJECT_DIR"

    # Verificar si es un proyecto Python válido
    if [ ! -f "requirements.txt" ] && [ ! -f "pyproject.toml" ] && [ ! -f "setup.py" ]; then
        echo "Error: No se encontró un proyecto Python válido en el directorio actual"
        exit 1
    fi

    # Usar ruta relativa desde el directorio de scripts
    TEMPLATES_DIR="$scripts_dir/support/templates/python/$TEMPLATE_TYPE"

    if [ ! -d "$TEMPLATES_DIR" ]; then
        echo "Error: No se encontró el directorio de plantillas en $TEMPLATES_DIR"
        exit 1
    fi

    echo -e "${BOLD}-----------------------------------------------${NC}"
    echo -e "${BOLD}Instalando templates Python ($TEMPLATE_TYPE).${NC}"
    echo -e "${BOLD}-----------------------------------------------${NC}"
    
    CapitalizedModuleName=$(echo "$TEMPLATE_NAME" | awk '{print toupper(substr($0, 1, 1)) tolower(substr($0, 2))}')
    camelCaseModuleName=$(echo "$TEMPLATE_NAME" | awk '{print tolower(substr($0, 1, 1)) substr($0, 2)}')
    snake_case_name=$(echo "$TEMPLATE_NAME" | sed 's/\([A-Z]\)/_\L\1/g' | sed 's/^_//')

    # Crear directorios para arquitectura hexagonal (estilo ejemplo_python)
    if [ "$TEMPLATE_TYPE" = "fastapi" ]; then
        # Dominio (núcleo de negocio)
        mkdir -p "domain/entities"
        
        # Aplicación (casos de uso y puertos)
        mkdir -p "application/services"
        mkdir -p "application/ports/driving/${snake_case_name}"
        mkdir -p "application/ports/driven/db/${snake_case_name}"
        mkdir -p "application/di"
        
        # Driving Adapters (entrada)
        mkdir -p "driving/api/${snake_case_name}/models"
        
        # Driven Adapters (salida)
        mkdir -p "driven/db/${snake_case_name}"
    elif [ "$TEMPLATE_TYPE" = "django" ]; then
        mkdir -p "models"
        mkdir -p "views"
        mkdir -p "serializers"
    fi

    generate_from_template() {
        local template_file=$1
        local output_file=$2

        if [ ! -f "$template_file" ]; then
            echo "Error: La plantilla no existe: $template_file"
            return 1
        fi

        # Generar el archivo reemplazando placeholders
        sed -e "s/{{TEMPLATE_NAME}}/$CapitalizedModuleName/g" \
            -e "s/{{PARAM_NAME}}/$snake_case_name/g" \
            -e "s/{{CAMEL_CASE}}/$camelCaseModuleName/g" "$template_file" > "$output_file"
        echo "✅ Archivo generado: $output_file"
    }

    # Generar archivos usando templates (estilo ejemplo_python)
    if [ "$TEMPLATE_TYPE" = "fastapi" ]; then
        # Archivos __init__.py para hacer los directorios paquetes Python
        generate_from_template "$TEMPLATES_DIR/domain/__init__" "domain/__init__.py"
        generate_from_template "$TEMPLATES_DIR/domain/entities/__init__" "domain/entities/__init__.py"
        generate_from_template "$TEMPLATES_DIR/application/__init__" "application/__init__.py"
        generate_from_template "$TEMPLATES_DIR/application/services/__init__" "application/services/__init__.py"
        generate_from_template "$TEMPLATES_DIR/application/ports/__init__" "application/ports/__init__.py"
        generate_from_template "$TEMPLATES_DIR/application/ports/driving/__init__" "application/ports/driving/__init__.py"
        generate_from_template "$TEMPLATES_DIR/application/ports/driven/__init__" "application/ports/driven/__init__.py"
        generate_from_template "$TEMPLATES_DIR/application/ports/driven/db/__init__" "application/ports/driven/db/__init__.py"
        generate_from_template "$TEMPLATES_DIR/application/di/__init__" "application/di/__init__.py"
        generate_from_template "$TEMPLATES_DIR/driving/__init__" "driving/__init__.py"
        generate_from_template "$TEMPLATES_DIR/driving/api/__init__" "driving/api/__init__.py"
        generate_from_template "$TEMPLATES_DIR/driven/__init__" "driven/__init__.py"
        generate_from_template "$TEMPLATES_DIR/driven/db/__init__" "driven/db/__init__.py"
        
        # __init__.py específicos del módulo
        echo "" > "application/ports/driving/${snake_case_name}/__init__.py"
        echo "" > "application/ports/driven/db/${snake_case_name}/__init__.py"
        echo "" > "driving/api/${snake_case_name}/__init__.py"
        echo "" > "driving/api/${snake_case_name}/models/__init__.py"
        echo "" > "driven/db/${snake_case_name}/__init__.py"
        
        # Capa de Dominio
        generate_from_template "$TEMPLATES_DIR/domain/entities/template" "domain/entities/${snake_case_name}.py"
        
        # Capa de Aplicación - Servicios
        generate_from_template "$TEMPLATES_DIR/application/services/template" "application/services/${snake_case_name}_service.py"
        
        # Capa de Aplicación - Puertos Driving
        generate_from_template "$TEMPLATES_DIR/application/ports/driving/service_port" "application/ports/driving/${snake_case_name}/service_port.py"
        generate_from_template "$TEMPLATES_DIR/application/ports/driving/api_port" "application/ports/driving/${snake_case_name}/api_port.py"
        
        # Capa de Aplicación - Puertos Driven
        generate_from_template "$TEMPLATES_DIR/application/ports/driven/db/repository_port" "application/ports/driven/db/${snake_case_name}/repository_port.py"
        
        # Capa de Aplicación - Dependencias
        generate_from_template "$TEMPLATES_DIR/application/di/dependencies" "application/di/${snake_case_name}_dependencies.py"
        
        # Driving Adapters - API
        generate_from_template "$TEMPLATES_DIR/driving/api/adapter" "driving/api/${snake_case_name}/adapter.py"
        generate_from_template "$TEMPLATES_DIR/driving/api/mapper" "driving/api/${snake_case_name}/mapper.py"
        generate_from_template "$TEMPLATES_DIR/driving/api/models/requests" "driving/api/${snake_case_name}/models/requests.py"
        generate_from_template "$TEMPLATES_DIR/driving/api/models/responses" "driving/api/${snake_case_name}/models/responses.py"
        
        # Driven Adapters - Base de Datos
        generate_from_template "$TEMPLATES_DIR/driven/db/adapter" "driven/db/${snake_case_name}/adapter.py"
        generate_from_template "$TEMPLATES_DIR/driven/db/mapper" "driven/db/${snake_case_name}/mapper.py"
        generate_from_template "$TEMPLATES_DIR/driven/db/models" "driven/db/${snake_case_name}/models.py"
    elif [ "$TEMPLATE_TYPE" = "django" ]; then
        generate_from_template "$TEMPLATES_DIR/view" "views/${snake_case_name}.py"
        generate_from_template "$TEMPLATES_DIR/serializer" "serializers/${snake_case_name}.py"
    fi
    
    echo ""
    echo -e "${GREEN}✅ Templates Python ($TEMPLATE_TYPE) generados correctamente para: $CapitalizedModuleName${NC}"
    echo -e "${GREEN}📁 Arquitectura Hexagonal implementada${NC}"
    echo ""
    echo -e "${YELLOW}📝 No olvides:${NC}"
    if [ "$TEMPLATE_TYPE" = "fastapi" ]; then
        echo -e "${YELLOW}   - Configurar Django ORM (settings.py y migraciones)${NC}"
        echo -e "${YELLOW}   - Registrar el modelo DBO en Django admin (opcional)${NC}"
        echo -e "${YELLOW}   - Importar el adaptador API en fastapi_app.py${NC}"
        echo -e "${YELLOW}   - Crear migraciones: python manage.py makemigrations${NC}"
        echo -e "${YELLOW}   - Aplicar migraciones: python manage.py migrate${NC}"
        echo ""
        echo -e "${BOLD}Estructura generada (Hexagonal Architecture):${NC}"
        echo -e "├── domain/entities/           (Entidades de dominio - Pydantic)"
        echo -e "├── application/               (Servicios, puertos, DI)"
        echo -e "│   ├── services/              (Lógica de aplicación)"
        echo -e "│   ├── ports/driving/         (Puertos de entrada)"
        echo -e "│   ├── ports/driven/          (Puertos de salida)"
        echo -e "│   └── di/                    (Inyección de dependencias)"
        echo -e "├── driving/api/               (Adaptadores FastAPI)"
        echo -e "└── driven/db/                 (Adaptadores Django ORM)"
    elif [ "$TEMPLATE_TYPE" = "django" ]; then
        echo -e "${YELLOW}   - Registrar las URLs en urls.py${NC}"
        echo -e "${YELLOW}   - Ejecutar makemigrations y migrate${NC}"
    fi
    echo ""
}