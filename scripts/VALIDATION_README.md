# Validación de archivos .gula

Este documento explica cómo usar el comando `validate` de gula para validar archivos de configuración `.gula` en tus proyectos.

## Descripción

El comando `validate` verifica que los archivos de configuración `.gula` cumplan con:

**Nota importante sobre nombres de archivo:**
- **Android, Flutter, Python**: Los archivos se llaman `configuration.gula`
- **iOS**: Los archivos tienen extensión `.gula` pero pueden tener cualquier nombre (ej: `Authentication.gula`, `Network.gula`) debido a restricciones del sistema de archivos de iOS

El comando `validate` detecta automáticamente el tipo de proyecto y busca los archivos correctamente.

1. **Formato JSON válido**: El archivo debe ser un JSON bien formado
2. **Estructura correcta**: Debe tener los campos esperados según la tecnología (Android, iOS, Flutter, Python)
3. **Referencias válidas**: Los módulos referenciados deben existir en el proyecto
4. **Dependencias correctas**: Las dependencias deben tener los campos requeridos

## Uso

### Validar todos los archivos del proyecto

```bash
gula validate
```

Este comando busca recursivamente todos los archivos `configuration.gula` en el proyecto y los valida.

**Ejemplo de salida:**

```
═══════════════════════════════════════════════
        VALIDACIÓN DE CONFIGURATION.GULA
═══════════════════════════════════════════════

✅ Tipo de proyecto detectado: Android

📋 Archivos encontrados: 3

──────────────────────────────────────────────
📄 Archivo: ./authentication/configuration.gula

  🔍 Validando formato JSON...
  ✅ JSON válido
  🔍 Validando configuración Android...
  🔍 Validando includes de Gradle...
    ✅ Includes de Gradle encontrados
  🔍 Validando módulos referenciados...
    ✅ Módulo encontrado: shared/components/customButton
    ✅ Módulo encontrado: shared/error
  🔍 Validando dependencias TOML...
    ✅ Dependencias TOML válidas (25 encontradas)

═══════════════════════════════════════════════
                    RESUMEN
═══════════════════════════════════════════════
✅ Archivos válidos: 3
⚠️  Advertencias: 0
❌ Errores: 0
───────────────────────────────────────────────

✅ Todos los archivos configuration.gula son válidos
```

### Validar solo archivos en staging (para pre-commit)

```bash
gula validate --staged
```

Este comando valida **solo** los archivos `configuration.gula` que están en staging de git (listos para commit). Es ideal para usarlo en pre-commit hooks.

**Ejemplo de salida:**

```
═══════════════════════════════════════════════
   VALIDACIÓN DE CONFIGURATION.GULA (STAGED)
═══════════════════════════════════════════════

Archivos configuration.gula encontrados en staging:
authentication/configuration.gula

✅ Tipo de proyecto detectado: Android

──────────────────────────────────────────────
📄 Archivo: authentication/configuration.gula
  🔍 Validando formato JSON...
  ✅ JSON válido
  ...

✅ Todos los archivos configuration.gula en staging son válidos
```

## Configurar Pre-commit Hook

### Opción 1: Instalación Automática (Recomendado)

Ejecuta el siguiente comando desde la raíz de tu proyecto:

```bash
gula install-hook
```

Este comando:
- ✅ Detecta si ya existe un pre-commit hook
- ✅ Te permite añadir la validación al hook existente o reemplazarlo
- ✅ Configura permisos automáticamente
- ✅ Verifica que estés en un repositorio git

**Ejemplo de uso:**

```bash
cd mi-proyecto
gula install-hook
```

**Salida:**

```
═══════════════════════════════════════════════
     INSTALACIÓN DE PRE-COMMIT HOOK (GULA)
═══════════════════════════════════════════════

✅ Pre-commit hook creado exitosamente
✅ Permisos de ejecución configurados

───────────────────────────────────────────────
🎉 Instalación completada

El pre-commit hook ahora validará automáticamente los
archivos configuration.gula antes de cada commit.
```

### Opción 2: Git Hook Manual

1. Copia el script de ejemplo:
```bash
cp /usr/local/share/gula/scripts/pre-commit-validation .git/hooks/pre-commit
```

2. Dale permisos de ejecución:
```bash
chmod +x .git/hooks/pre-commit
```

### Opción 3: Pre-commit Framework (Python)

Si usas [pre-commit](https://pre-commit.com/), añade esto a tu `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: local
    hooks:
      - id: validate-configuration-gula
        name: Validate configuration.gula files
        entry: gula validate --staged
        language: system
        files: 'configuration\.gula$'
        pass_filenames: false
```

Luego instala el hook:
```bash
pre-commit install
```

### Opción 4: Husky (JavaScript/Node)

Si usas [Husky](https://typicode.github.io/husky/), añade en tu `package.json`:

```json
{
  "husky": {
    "hooks": {
      "pre-commit": "gula validate --staged"
    }
  }
}
```

O con Husky v6+:
```bash
npx husky add .husky/pre-commit "gula validate --staged"
```

## Validaciones por Tecnología

### Android

Para proyectos Android (`configuration.gula`), se valida:

- ✅ Sección `gradle.includes[]` - Módulos de Gradle
- ✅ Sección `gradle.dependencies[]` - Repositorios Maven con `name` y `url`
- ✅ Sección `toml[]` - Dependencias con estructura completa:
  - Cada dependencia debe tener `name`, `version`, `id`
  - Cada dependencia debe tener `module`, `plugin` o `group`
    - `module`: Para dependencias como `"com.google.dagger:hilt-android"`
    - `group`: Para dependencias como `"androidx.appcompat"` (se combina con `name`)
    - `plugin`: Para plugins de Gradle
- ✅ Sección `modules[]` - Rutas a módulos que deben existir en el proyecto

**Ejemplo válido:**

```json
{
    "toml": [
        {
            "name": "appcompat",
            "version": "1.7.0",
            "id": "androidx-appcompat",
            "group": "androidx.appcompat"
        },
        {
            "name": "hilt-android",
            "version": "2.51",
            "id": "hilt-android",
            "module": "com.google.dagger:hilt-android"
        },
        {
            "name": "kotlin",
            "version": "1.9.0",
            "id": "jetbrains-kotlin-android",
            "plugin": "org.jetbrains.kotlin.android"
        }
    ],
    "gradle": {
        "includes": [":authentication"],
        "dependencies": [
            {
                "name": "maven",
                "url": "https://jitpack.io"
            }
        ]
    },
    "modules": [
        "shared/components/customButton",
        "shared/network"
    ]
}
```

### iOS

Para proyectos iOS (archivos `*.gula`), se valida:

- ✅ Sección `libraries[]` - Swift Package Manager
  - Cada librería debe tener `name`, `url`, `version`
- ✅ Sección `shared[]` - Rutas a módulos compartidos
  - Las rutas pueden empezar con `Gula/` (desde repositorio) o ser locales
  - Se verifica que las rutas existan

**Ejemplo válido:**

```json
{
    "shared": [
        "Gula/Shared/Error",
        "Gula/Shared/Configuration",
        "Gula/Shared/Navigator"
    ],
    "libraries": [
        {
            "name": "TripleA",
            "url": "https://github.com/fsalom/TripleA",
            "version": "2.3.0"
        }
    ]
}
```

### Flutter

Para proyectos Flutter (`configuration.gula`), se valida:

- ✅ Sección `libraries[]` - Dependencias principales
  - Cada librería debe tener `name`
  - Debe tener `version` o `git.url` (y opcionalmente `git.ref`)
- ✅ Sección `dev_libraries[]` - Dependencias de desarrollo (misma estructura que `libraries`)
- ✅ Sección `shared[]` - Rutas a módulos compartidos (relativas a `lib/`)

**Ejemplo válido:**

```json
{
    "libraries": [
        {
            "name": "http",
            "version": "^1.1.0"
        },
        {
            "name": "custom_package",
            "git": {
                "url": "https://github.com/user/package",
                "ref": "main"
            }
        }
    ],
    "dev_libraries": [
        {
            "name": "mockito",
            "version": "^5.4.0"
        }
    ],
    "shared": [
        "core/network",
        "core/error"
    ]
}
```

### Python

Para proyectos Python (`configuration.gula`), se valida:

- ✅ Estructura básica de JSON
- ✅ Sección `modules[]` si existe

**Nota:** Python tiene una estructura de instalación diferente a otras plataformas.

## Códigos de Salida

- `0`: Validación exitosa (todos los archivos son válidos)
- `1`: Errores encontrados (hay archivos con errores críticos)
- `2`: Advertencias encontradas (archivos válidos pero con advertencias)

En pre-commit hooks, solo el código `1` (errores) bloqueará el commit.

## Solución de Problemas

### "JSON inválido"

**Problema:** El archivo no es un JSON bien formado

**Solución:** Usa un validador JSON o un editor con resaltado de sintaxis para encontrar el error:
```bash
jq empty configuration.gula
```

### "Módulo no encontrado"

**Problema:** Un módulo referenciado en `modules` no existe

**Solución:**
- Verifica que la ruta del módulo sea correcta
- Verifica que el módulo exista en el proyecto
- Si el módulo fue eliminado, elimínalo de la lista de `modules`

### "Dependencia sin 'id'"

**Problema:** Una dependencia en `toml` no tiene el campo `id`

**Solución:** Añade el campo `id` a la dependencia:
```json
{
    "name": "retrofit",
    "version": "2.11.0",
    "id": "retrofit",  // ← Añade este campo
    "module": "com.squareup.retrofit2:retrofit"
}
```

## Ejemplos Completos

### Android - authentication/configuration.gula

```json
{
    "toml": [
        {
            "name": "hilt-android",
            "version": "2.51",
            "id": "hilt-android",
            "module": "com.google.dagger:hilt-android"
        }
    ],
    "gradle": {
        "includes": [":authentication"],
        "dependencies": [
            {
                "name": "maven",
                "url": "https://jitpack.io"
            }
        ]
    },
    "modules": [
        "shared/components/customButton",
        "shared/error",
        "shared/network"
    ]
}
```

### Flutter - features/user/configuration.gula

```json
{
    "dependencies": {
        "http": "^1.1.0",
        "provider": "^6.0.0"
    },
    "dev_dependencies": {
        "mockito": "^5.4.0"
    },
    "modules": [
        "core/network",
        "core/error"
    ]
}
```

### iOS - Features/Authentication/configuration.gula

```json
{
    "pods": [
        {
            "name": "Alamofire",
            "version": "~> 5.6"
        }
    ],
    "modules": [
        "Shared/Network",
        "Shared/Error"
    ]
}
```

## Integración Continua (CI/CD)

Puedes usar `gula validate` en tu pipeline de CI/CD:

### GitHub Actions

```yaml
- name: Validate configuration.gula
  run: gula validate
```

### GitLab CI

```yaml
validate:
  script:
    - gula validate
```

### Jenkins

```groovy
stage('Validate') {
    steps {
        sh 'gula validate'
    }
}
```
