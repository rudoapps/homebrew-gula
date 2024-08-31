
# Gula Installer

Versión: 0.0.17
Propiedad: Rudo Apps

# Descripción
El Gula Module Installer es un script bash diseñado para facilitar la instalación y gestión de módulos en proyectos Android e iOS. Este script permite identificar el tipo de proyecto (Android o iOS) y ejecutar los comandos correspondientes para instalar o listar módulos en dichos proyectos.

# Requisitos
Antes de utilizar el script, asegúrate de cumplir con los siguientes requisitos:

Homebrew: El script depende de Homebrew para gestionar algunos recursos, asegúrate de tenerlo instalado.

```
brew tap rudoapps/gula
```

```
brew install gula
```

# Actualización

```
brew untap rudoapps/gula
brew uninstall gula
brew tap rudoapps/gula
brew install gula
```

# Uso
Sintaxis básica

```
gula {install|list} [nombre-del-modulo] [--key=xxxx]
```

Comandos disponibles

install: Instala un módulo en el proyecto. Debes especificar el nombre del módulo a instalar.

```
gula install nombre-del-modulo [--key=xxxx]
```

list: Lista los módulos disponibles para el proyecto actual.

```
gula list [--key=xxxx]
```

# Opciones

--key=xxxx: Proporciona una clave de acceso si es necesaria para la instalación del módulo.

# Ejemplos de uso

Instalar un módulo en un proyecto Android o iOS:

```
gula install authentication --key=1234abcd
```

Listar los módulos disponibles en un proyecto:

```
gula list --key=1234abcd
```

# Mantenimiento

El script incluye funciones para limpiar los directorios temporales utilizados durante el proceso de instalación. Si es necesario, se puede interrumpir el proceso con Ctrl + C, y el script ejecutará automáticamente la limpieza mediante la función cleanup.

# Contribuir

Si deseas contribuir a este proyecto, no dudes en hacer un fork del repositorio, realizar tus modificaciones y enviar un pull request.

# Licencia

Este script es propiedad de Rudo Apps y está bajo los términos que se describen en el archivo de licencia adjunto (si corresponde).

Este README proporciona una guía completa sobre cómo utilizar tu script, desde los requisitos previos hasta ejemplos de uso práctico.