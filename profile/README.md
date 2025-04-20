# 🌟 **MicroTodoSuite** - Aplicación TODO basada en microservicios

**🚀 Bienvenidos a _MicroTodoSuite_**
Un entorno experimental que integra una aplicación TODO simple compuesta por microservicios independientes. Esta organización está orientada al despliegue automatizado de infraestructura en la nube utilizando herramientas modernas de infraestructura como código.

## 📌 **Naturaleza del Proyecto**

**🔹 Objetivo Principal:**
Automatizar el aprovisionamiento y despliegue de una infraestructura en Azure que soporte una aplicación basada en microservicios. El enfoque está en prácticas de DevOps, orquestación de recursos, y monitoreo del sistema.

## 👥 **Equipos y Roles**

| Equipo            | Integrantes | Conocimientos Clave                     | Responsabilidades                           |
| ----------------- | ----------- | --------------------------------------- | ------------------------------------------- |
| **🧑‍💻 Desarrollo** | 3           | Node.js, Python, Vue.js, APIs REST      | Desarrollo de microservicios y frontend     |
| **🛠️ DevOps/Ops** | 3           | Azure, Terraform, CI/CD, observabilidad | Infraestructura, automatización y monitoreo |

## 🧩 **Microservicios**

| Servicio            | Tecnología         | Descripción                       | Estado    |
| ------------------- | ------------------ | --------------------------------- | --------- |
| **`auth-api`**      | Go                 | Servicio de autenticación con JWT | 🟢 Activo |
| **`todos-api`**     | Node.js            | CRUD de tareas                    | 🟢 Activo |
| **`users-api`**     | Java (Spring Boot) | Gestión de usuarios               | 🟢 Activo |
| **`frontend`**      | Vue.js             | Interfaz de usuario               | 🟢 Activo |
| **`log-processor`** | Python             | Procesamiento de logs             | 🟢 Activo |

## 📂 **Estructura de Repositorios**

1. **`MicroTodoSuite/microservice-app-dev`** (GitHub Flow 🌿)  
   Repositorio con el código fuente de los microservicios y el frontend.

   - Ramas: `feat/*` → Pull Request a `main`.

2. **`MicroTodoSuite/microservice-app-ops`** (Trunk-Based Development 🚀)  
   Contiene la infraestructura como código escrita en Terraform para aprovisionamiento en Azure.

   - Ramas: cambios directos en `main` con revisión colaborativa.

3. **`MicroTodoSuite/microservice-app-docs`** (Wiki 📖)
   Documentación técnica y diagramas de arquitectura del sistema.

## 📊 **Monitoreo y Observabilidad**

La solución incluye un sistema de monitoreo basado en Prometheus y Grafana para obtener métricas del comportamiento del sistema en tiempo real.

- **🔍 Prometheus:** recolecta métricas de los contenedores y servicios expuestos, almacenándolas en una base de datos de series temporales.
- **📈 Grafana:** genera visualizaciones interactivas para analizar el estado de la aplicación, como uso de CPU, memoria, tráfico de red y actividad del sistema.

Ambas herramientas se integran como parte de la infraestructura desplegada y permiten evaluar el rendimiento y detectar cuellos de botella operativos.
