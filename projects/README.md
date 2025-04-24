# Script de Creación de Proyectos en GitHub

Este script automatiza la creación de dos proyectos en una organización de GitHub usando GitHub CLI.

## Requisitos previos

1. Instalar GitHub CLI:

   ```bash
   sudo apt install gh
   ```

2. Autenticarse en GitHub:

   ```bash
   gh auth login
   ```

   - Se abrirá tu navegador para completar la autenticación
   - Selecciona "GitHub.com" como host
   - Elige "HTTPS" como protocolo
   - Marca "Login with a web browser"

## Uso del Script

Ejecuta el script con:

```bash
./create-projects.sh
```

El script creará automáticamente dos proyectos en la organización especificada.
