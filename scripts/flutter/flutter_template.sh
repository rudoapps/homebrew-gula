#!/bin/bash

flutter_install_all_templates() {
    # Validar entrada
    if [ -z "$1" ]; then
        echo "Error: Debes proporcionar un nombre para el módulo o caso de uso."
        echo "Uso: gula template <ModuleName> [--type=clean|bloc|provider]"
        exit 1
    fi

    local TEMPLATE_NAME=$1
    local TEMPLATE_TYPE=${TEMPLATE_TYPE:-clean}
    
    PROJECT_DIR=$(pwd)
    echo ""
    echo "Generando templates para Flutter en: $PROJECT_DIR"

    # Verificar si es un proyecto Flutter válido
    if [ ! -f "pubspec.yaml" ]; then
        echo "Error: No se encontró un proyecto Flutter válido en el directorio actual"
        exit 1
    fi

    # Usar ruta relativa desde el directorio de scripts
    TEMPLATES_DIR="$scripts_dir/support/templates/flutter/$TEMPLATE_TYPE"

    if [ ! -d "$TEMPLATES_DIR" ]; then
        echo "Error: No se encontró el directorio de plantillas en $TEMPLATES_DIR"
        exit 1
    fi

    echo -e "${BOLD}-----------------------------------------------${NC}"
    echo -e "${BOLD}Instalando templates Flutter ($TEMPLATE_TYPE).${NC}"
    echo -e "${BOLD}-----------------------------------------------${NC}"
    
    CapitalizedModuleName=$(echo "$TEMPLATE_NAME" | awk '{print toupper(substr($0, 1, 1)) tolower(substr($0, 2))}')
    camelCaseModuleName=$(echo "$TEMPLATE_NAME" | awk '{print tolower(substr($0, 1, 1)) substr($0, 2)}')
    snake_case_name=$(echo "$TEMPLATE_NAME" | sed 's/\([A-Z]\)/_\L\1/g' | sed 's/^_//')

    # Crear directorios necesarios para Clean Architecture
    BASE_PATH="lib/features/$snake_case_name"
    
    mkdir -p "$BASE_PATH/domain/entities"
    mkdir -p "$BASE_PATH/domain/repositories"
    mkdir -p "$BASE_PATH/domain/usecases"
    mkdir -p "$BASE_PATH/data/models"
    mkdir -p "$BASE_PATH/data/datasources"
    mkdir -p "$BASE_PATH/data/repositories"
    mkdir -p "$BASE_PATH/presentation/bloc"
    mkdir -p "$BASE_PATH/presentation/pages"
    mkdir -p "$BASE_PATH/presentation/widgets"

    generate_from_template() {
        local template_file=$1
        local output_file=$2

        if [ ! -f "$template_file" ]; then
            echo "Error: La plantilla no existe: $template_file"
            return 1
        fi

        # Generar el archivo reemplazando placeholders
        sed -e "s/{{TEMPLATE_NAME}}/$CapitalizedModuleName/g" \
            -e "s/{{PARAM_NAME}}/$camelCaseModuleName/g" \
            -e "s/{{SNAKE_CASE}}/$snake_case_name/g" "$template_file" > "$output_file"
        echo "✅ Archivo generado: $output_file"
    }

    # Generar archivos usando templates
    generate_from_template "$TEMPLATES_DIR/domain_entity" "$BASE_PATH/domain/entities/${snake_case_name}.dart"
    generate_from_template "$TEMPLATES_DIR/domain_repository" "$BASE_PATH/domain/repositories/${snake_case_name}_repository.dart"
    generate_from_template "$TEMPLATES_DIR/domain_usecase" "$BASE_PATH/domain/usecases/${snake_case_name}_usecases.dart"
    
    generate_from_template "$TEMPLATES_DIR/data_model" "$BASE_PATH/data/models/${snake_case_name}_model.dart"
    generate_from_template "$TEMPLATES_DIR/data_datasource" "$BASE_PATH/data/datasources/${snake_case_name}_remote_data_source.dart"
    generate_from_template "$TEMPLATES_DIR/data_repository" "$BASE_PATH/data/repositories/${snake_case_name}_repository_impl.dart"
    
    generate_from_template "$TEMPLATES_DIR/presentation_bloc" "$BASE_PATH/presentation/bloc/${snake_case_name}_bloc.dart"
    generate_from_template "$TEMPLATES_DIR/presentation_event" "$BASE_PATH/presentation/bloc/${snake_case_name}_event.dart"
    generate_from_template "$TEMPLATES_DIR/presentation_state" "$BASE_PATH/presentation/bloc/${snake_case_name}_state.dart"
    generate_from_template "$TEMPLATES_DIR/presentation_page" "$BASE_PATH/presentation/pages/${snake_case_name}_page.dart"
    
    echo ""
    echo -e "${GREEN}✅ Templates Flutter generados correctamente para: $CapitalizedModuleName${NC}"
    echo -e "${GREEN}📁 Archivos creados en: $BASE_PATH${NC}"
    echo ""
    echo -e "${YELLOW}📝 No olvides:${NC}"
    echo -e "${YELLOW}   - Agregar las dependencias necesarias en pubspec.yaml${NC}"
    echo -e "${YELLOW}   - Configurar la inyección de dependencias${NC}"
    echo -e "${YELLOW}   - Registrar las rutas en tu app${NC}"
    echo ""
}