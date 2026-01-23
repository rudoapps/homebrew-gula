# Gula

## Descripcion

Gula es una herramienta CLI para acelerar el desarrollo con arquetipos y modulos predefinidos. Soporta proyectos **Android**, **iOS**, **Flutter** y **Python**.

## Requisitos

Antes de utilizar gula, asegurate de tener instalado Homebrew: https://brew.sh/

```bash
brew tap rudoapps/gula
brew install gula
```

## Actualizacion

Recomendamos mantener gula actualizado:

```bash
brew update && brew upgrade gula
```

## Uso

```bash
gula <comando> [opciones]
```

## Comandos disponibles

### Agente AI

| Comando | Descripcion |
|---------|-------------|
| `chat` | Inicia conversacion con el agente AI |
| `login` | Inicia sesion en el agente AI |
| `logout` | Cierra sesion del agente AI |
| `setup` | Instala dependencias del agente AI |
| `whoami` | Muestra el usuario actual del agente |
| `undo` | Lista y restaura backups de archivos modificados |

### Modulos y Proyectos

| Comando | Descripcion |
|---------|-------------|
| `list` | Lista modulos disponibles para el proyecto actual |
| `install` | Instala uno o varios modulos en el proyecto |
| `create` | Crea un nuevo proyecto con arquitectura predefinida |
| `template` | Genera templates con arquitecturas predefinidas |
| `branches` | Lista ramas disponibles en repositorios |
| `status` | Muestra el estado del proyecto y modulos instalados |
| `validate` | Valida archivos configuration.gula del proyecto |
| `install-hook` | Instala pre-commit hook para validar configuration.gula |
| `help` | Muestra la ayuda |

## Opciones globales

| Opcion | Descripcion |
|--------|-------------|
| `--key=XXXX` | Clave de acceso para repositorios privados |
| `--branch=YYYY` | Rama especifica del repositorio |
| `--tag=ZZZZ` | Tag especifico del repositorio |
| `--type=ZZZZ` | Tipo de template: `clean`, `fastapi` |
| `--archetype=ZZZZ` | Plataforma: `android`, `ios`, `flutter`, `python` |
| `--force` | Forzar reinstalacion sin confirmar |
| `--module` | Instalar como modulo completo (modo por defecto) |
| `--integrate` | [Solo iOS] Integrar en estructura existente |
| `--list` | Lista todos los templates disponibles |
| `--json` | Salida en formato JSON |
| `--help`, `-h` | Muestra la ayuda |

## Ejemplos de uso

### Usar el agente AI

```bash
# Instalar dependencias del agente
gula setup

# Iniciar sesion
gula login

# Modo interactivo
gula chat

# Mensaje unico
gula chat "Hola"

# Continuar ultima conversacion
gula chat --continue

# Ver usuario actual
gula whoami

# Cerrar sesion
gula logout
```

### Listar modulos disponibles

```bash
gula list --key=mi_clave
gula list --key=mi_clave --branch=development
```

### Instalar modulos

```bash
# Instalar un modulo
gula install authentication --key=mi_clave

# Instalar con rama especifica
gula install network --key=mi_clave --branch=feature-branch

# Instalar con tag especifico
gula install network --key=mi_clave --tag=v1.0.0

# Forzar reinstalacion
gula install authentication --key=mi_clave --force

# Instalar como modulo completo (sin preguntar)
gula install authentication --key=mi_clave --module

# [iOS] Integrar en capas existentes (data→data, domain→domain)
gula install authentication --key=mi_clave --integrate

# Instalar multiples modulos (batch)
gula install login,wallet,payments --key=mi_clave
```

### Crear nuevos proyectos

```bash
gula create android --key=mi_clave
gula create ios --key=mi_clave
gula create flutter --key=mi_clave
gula create python --key=mi_clave
```

### Generar templates

```bash
# Ver templates disponibles
gula template --list

# Generar un template
gula template user
gula template product --type=clean

# Generar multiples templates
gula template user,product,order
```

### Listar ramas disponibles

```bash
# Auto-detecta el tipo de proyecto
gula branches --key=mi_clave

# Para consultar arquetipos especificos
gula branches --key=mi_clave --archetype=flutter
```

### Ver estado del proyecto

```bash
gula status
```

### Validar configuracion

```bash
# Validar todos los configuration.gula
gula validate

# Validar solo archivos en staging (pre-commit)
gula validate --staged

# Instalar hook de pre-commit
gula install-hook
```

## Plataformas soportadas

| Plataforma | Descripcion |
|------------|-------------|
| Android | Proyectos nativos Android con Clean Architecture |
| iOS | Proyectos nativos iOS con Clean Architecture |
| Flutter | Aplicaciones multiplataforma Flutter |
| Python | APIs backend con FastAPI o Django |

## Arquitecturas disponibles

- **Android & iOS**: Clean Architecture (Repository, UseCase, ViewModel)
- **Flutter**: Clean Architecture (BLoC, Repository, UseCase)
- **Python**: Arquitectura Hexagonal (Adaptadores y Puertos)

## Notas

- `chat/login/setup`: Comandos del agente AI, usa `gula setup` primero para instalar dependencias
- `template`: No requiere `--key` (usa templates locales)
- `install/list`: Requiere `--key` para acceder a repositorios privados
- `create`: Requiere `--key` para descargar arquetipos
- `--integrate`: Solo disponible para proyectos iOS
- Los comandos `list/install` detectan automaticamente el tipo de proyecto
- Todas las operaciones se registran en `.gula.log` (formato JSON)
- Use `gula status` para ver el historial de operaciones

## Contribuir

Si deseas contribuir a este proyecto, haz un fork del repositorio, realiza tus modificaciones y envia un pull request.

## Licencia

Este proyecto es propiedad de Rudo Apps y esta bajo licencia MIT.
