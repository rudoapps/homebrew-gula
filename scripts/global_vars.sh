#!/bin/bash

TEMPORARY_DIR="temp-gula"
MODULE_NAME=""
KEY=""
ACCESSTOKEN=""
GULA_COMMAND=""
VERSION="0.0.147"

# Definir colores
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'
NC='\033[0m'

# Colores para gum (256 colors)
GUM_ACCENT="212"      # Rosa/magenta
GUM_SUBTLE="240"      # Gris
GUM_SUCCESS="78"      # Verde
GUM_WARNING="214"     # Naranja