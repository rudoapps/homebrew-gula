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

    # Preserve original PascalCase naming (UserProfile stays UserProfile)
    CapitalizedModuleName="$TEMPLATE_NAME"
    camelCaseModuleName=$(echo "$TEMPLATE_NAME" | awk '{print tolower(substr($0, 1, 1)) substr($0, 2)}')
    # Convertir a snake_case correctamente (UserProfile -> user_profile)
    snake_case_name=$(echo "$TEMPLATE_NAME" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' | tr '[:upper:]' '[:lower:]')

    # Crear estructura de directorios completa para Clean Architecture según layers/
    echo "📁 Creando estructura de carpetas..."

    # Domain Layer
    mkdir -p "lib/layers/domain/entities/$snake_case_name"
    mkdir -p "lib/layers/domain/repositories/$snake_case_name"
    mkdir -p "lib/layers/domain/use_cases/$snake_case_name"

    # Data Layer - DataSources
    mkdir -p "lib/layers/data/datasources/$snake_case_name/source"
    mkdir -p "lib/layers/data/datasources/$snake_case_name/remote/dto"
    mkdir -p "lib/layers/data/datasources/$snake_case_name/local/dbo"

    # Data Layer - Repositories
    mkdir -p "lib/layers/data/repositories/$snake_case_name/mapper"

    # Presentation Layer
    mkdir -p "lib/layers/presentation/features/$snake_case_name/bloc"

    generate_from_template() {
        local template_file=$1
        local output_file=$2

        if [ ! -f "$template_file" ]; then
            echo "❌ Error: La plantilla no existe: $template_file"
            return 1
        fi

        # Generar el archivo reemplazando placeholders
        sed -e "s/{{TEMPLATE_NAME}}/$CapitalizedModuleName/g" \
            -e "s/{{PARAM_NAME}}/$snake_case_name/g" \
            -e "s/{{SNAKE_CASE}}/$snake_case_name/g" "$template_file" > "$output_file"
        echo "   ✅ $output_file"
    }

    echo ""
    echo "📝 Generando archivos desde templates..."
    echo ""

    # === DOMAIN LAYER ===
    echo "🔷 Domain Layer:"
    generate_from_template "$TEMPLATES_DIR/domain_entity" \
        "lib/layers/domain/entities/$snake_case_name/${snake_case_name}_entity.dart"

    generate_from_template "$TEMPLATES_DIR/domain_repository" \
        "lib/layers/domain/repositories/$snake_case_name/${snake_case_name}_repository.dart"

    generate_from_template "$TEMPLATES_DIR/domain_usecase" \
        "lib/layers/domain/use_cases/$snake_case_name/${snake_case_name}_use_case.dart"

    echo ""

    # === DATA LAYER - DATASOURCES ===
    echo "🔷 Data Layer - DataSources:"

    # Interfaces
    generate_from_template "$TEMPLATES_DIR/data_datasource_remote_source" \
        "lib/layers/data/datasources/$snake_case_name/source/${snake_case_name}_remote_data_source.dart"

    generate_from_template "$TEMPLATES_DIR/data_datasource_local_source" \
        "lib/layers/data/datasources/$snake_case_name/source/${snake_case_name}_local_data_source.dart"

    # Remote Implementation + DTO
    generate_from_template "$TEMPLATES_DIR/data_datasource_remote_impl" \
        "lib/layers/data/datasources/$snake_case_name/remote/${snake_case_name}_remote_data_source_impl.dart"

    generate_from_template "$TEMPLATES_DIR/data_dto" \
        "lib/layers/data/datasources/$snake_case_name/remote/dto/${snake_case_name}_response_dto.dart"

    # Local Implementation + DBO
    generate_from_template "$TEMPLATES_DIR/data_datasource_local_impl" \
        "lib/layers/data/datasources/$snake_case_name/local/${snake_case_name}_local_data_source_impl.dart"

    generate_from_template "$TEMPLATES_DIR/data_dbo" \
        "lib/layers/data/datasources/$snake_case_name/local/dbo/${snake_case_name}_dbo.dart"

    echo ""

    # === DATA LAYER - REPOSITORIES ===
    echo "🔷 Data Layer - Repositories:"

    generate_from_template "$TEMPLATES_DIR/data_repository" \
        "lib/layers/data/repositories/$snake_case_name/${snake_case_name}_repository_impl.dart"

    generate_from_template "$TEMPLATES_DIR/data_mapper_dto" \
        "lib/layers/data/repositories/$snake_case_name/mapper/${snake_case_name}_mapper_dto.dart"

    generate_from_template "$TEMPLATES_DIR/data_mapper_dbo" \
        "lib/layers/data/repositories/$snake_case_name/mapper/${snake_case_name}_mapper_dbo.dart"

    echo ""

    # === PRESENTATION LAYER ===
    echo "🔷 Presentation Layer:"

    generate_from_template "$TEMPLATES_DIR/presentation_page" \
        "lib/layers/presentation/features/$snake_case_name/${snake_case_name}_page.dart"

    generate_from_template "$TEMPLATES_DIR/presentation_bloc" \
        "lib/layers/presentation/features/$snake_case_name/bloc/${snake_case_name}_bloc.dart"

    generate_from_template "$TEMPLATES_DIR/presentation_event" \
        "lib/layers/presentation/features/$snake_case_name/bloc/${snake_case_name}_event.dart"

    generate_from_template "$TEMPLATES_DIR/presentation_state" \
        "lib/layers/presentation/features/$snake_case_name/bloc/${snake_case_name}_state.dart"

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Templates Flutter generados exitosamente!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BOLD}📊 Resumen:${NC}"
    echo -e "   • Feature: ${BOLD}$CapitalizedModuleName${NC}"
    echo -e "   • Archivos generados: ${BOLD}17${NC}"
    echo -e "   • Ubicación: ${BOLD}lib/layers/${NC}"
    echo ""
    echo -e "${YELLOW}📋 Estructura generada:${NC}"
    echo -e "   lib/layers/"
    echo -e "   ├── domain/"
    echo -e "   │   ├── entities/$snake_case_name/"
    echo -e "   │   ├── repositories/$snake_case_name/"
    echo -e "   │   └── use_cases/$snake_case_name/"
    echo -e "   ├── data/"
    echo -e "   │   ├── datasources/$snake_case_name/"
    echo -e "   │   │   ├── source/ (interfaces)"
    echo -e "   │   │   ├── remote/ (impl + dto)"
    echo -e "   │   │   └── local/ (impl + dbo)"
    echo -e "   │   └── repositories/$snake_case_name/"
    echo -e "   │       └── mapper/"
    echo -e "   └── presentation/"
    echo -e "       └── features/$snake_case_name/"
    echo -e "           └── bloc/"
    echo ""
    echo -e "${YELLOW}📝 Próximos pasos:${NC}"
    echo -e "   1. Revisar y personalizar los archivos generados"
    echo -e "   2. Actualizar los imports si es necesario"
    echo -e "   3. Implementar la lógica de negocio"
    echo -e "   4. Ejecutar: ${BOLD}dart run build_runner build${NC} (para DI)"
    echo -e "   5. Agregar la ruta en tu navegación"
    echo ""
}
