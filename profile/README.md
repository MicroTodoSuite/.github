# 🌟 **MicroTodoSuite** - Aplicación TODO basada en microservicios

**🚀 Bienvenidos a _MicroTodoSuite_**,  
una solución diseñada, desarrollada y gestionada por **GaCode Solutions**.

MicroTodoSuite es una plataforma experimental que ejemplifica las mejores prácticas en desarrollo basado en
microservicios y despliegue automatizado de infraestructura en la nube. Este ecosistema ha sido concebido por GaCode
Solutions con el propósito de servir como referencia operativa para entornos modernos, escalables y observables.

---

## 📌 **Naturaleza del Proyecto**

**🔹 Objetivo Principal:**
Desde **GaCode Solutions**, nuestro objetivo con MicroTodoSuite es demostrar un modelo integral de aprovisionamiento y
despliegue automatizado en **Microsoft Azure**, apoyándonos en tecnologías de infraestructura como código, prácticas de
**DevOps** modernas, y soluciones robustas de monitoreo y observabilidad.

---

## 👥 **Equipos y Roles**

Los equipos involucrados en MicroTodoSuite están conformados por especialistas de **GaCode Solutions**, con experiencia
consolidada en desarrollo de software y operaciones de infraestructura en la nube.

| Equipo               | Integrantes | Conocimientos Clave                     | Responsabilidades                                      |
|----------------------|-------------|-----------------------------------------|--------------------------------------------------------|
| **🧑‍💻 Desarrollo** | 3           | Node.js, Python, Vue.js, GO, APIs REST  | Implementación del frontend y microservicios           |
| **🛠️ DevOps/Ops**   | 3           | Azure, Terraform, CI/CD, observabilidad | Gestión de infraestructura, automatización y monitoreo |

---

## 🧩 **Microservicios Desplegados**

La arquitectura se compone de los siguientes microservicios, todos desarrollados y mantenidos por **GaCode Solutions**:

| Servicio            | Tecnología         | Descripción                       | Estado    |
|---------------------|--------------------|-----------------------------------|-----------|
| **`auth-api`**      | Go                 | Servicio de autenticación con JWT | 🟢 Activo |
| **`todos-api`**     | Node.js            | CRUD de tareas                    | 🟢 Activo |
| **`users-api`**     | Java (Spring Boot) | Gestión de usuarios               | 🟢 Activo |
| **`frontend`**      | Vue.js             | Interfaz de usuario               | 🟢 Activo |
| **`log-processor`** | Python             | Procesamiento de logs             | 🟢 Activo |

---

## 📂 **Estructura de Repositorios**

Para garantizar un desarrollo organizado y colaborativo, GaCode Solutions estructura los repositorios de la siguiente
manera:

1. **`MicroTodoSuite/microservice-app-dev`** (GitHub Flow 🌿)  
   Código fuente de los microservicios y la interfaz web.
    - Flujo: ramas `feat/*` con Pull Requests hacia `main`.

2. **`MicroTodoSuite/microservice-app-ops`** (Trunk-Based Development 🚀)  
   Repositorio dedicado a la infraestructura como código en Terraform, orientado al aprovisionamiento automatizado en
   Azure.
    - Flujo: commits directos en `main` con revisión cruzada entre los ingenieros DevOps.

3. **`MicroTodoSuite/microservice-app-docs`** (Wiki 📖)  
   Repositorio de documentación técnica, diagramas de arquitectura y decisiones de diseño.

---

## 📊 **Monitoreo y Observabilidad**

**GaCode Solutions** ha integrado un stack de monitoreo robusto que permite evaluar el rendimiento y la estabilidad del
sistema en tiempo real.

- **🔍 Prometheus**: recolecta métricas de los servicios y contenedores desplegados, almacenándolas como series
  temporales.
- **📈 Grafana**: visualiza los datos en paneles interactivos, facilitando el análisis de uso de recursos, tráfico y
  comportamiento del sistema.

Estas herramientas están completamente integradas dentro del entorno automatizado y son fundamentales para garantizar
una operación eficiente y escalable.
