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

En **GaCode Solutions**, apostamos por una arquitectura modular basada en múltiples repositorios, lo que permite una
mayor autonomía, trazabilidad y escalabilidad en el ciclo de vida de cada componente.

A continuación, se detallan los repositorios que componen el ecosistema de **MicroTodoSuite**:

### 🧱 **Repositorios de Aplicación (GitHub Flow 🌿)**

Cada microservicio se mantiene de forma independiente para facilitar despliegues desacoplados y evolución por separado.

| Repositorio                              | Descripción                                     |
|------------------------------------------|-------------------------------------------------|
| `microservice-app-auth-api`              | Servicio de autenticación (Go + JWT)            |
| `microservice-app-todos-api`             | Gestión de tareas (Node.js)                     |
| `microservice-app-users-api`             | Administración de usuarios (Java - Spring Boot) |
| `microservice-app-frontend`              | Interfaz de usuario (Vue.js)                    |
| `microservice-app-log-message-processor` | Procesador de logs del sistema (Python)         |

> 🔄 **Flujo de trabajo:**  
> Ramas `feat/*` → Pull Request → `main`. Cada cambio pasa por revisión antes de integrarse.

---

### 🛠 **Repositorio de Infraestructura (Trunk-Based Development 🚀)**

- **`microservice-app-ops`**  
  Contiene la infraestructura como código escrita en **Terraform**. Automatiza el aprovisionamiento en Microsoft Azure.

> 🔁 **Flujo de trabajo:**  
> Commits directos a `main`, bajo revisión colaborativa de los ingenieros DevOps.

---

### 📖 **Repositorio de Documentación**

- **`microservice-app-docs`**  
  Reúne documentación técnica, diagramas de arquitectura, decisiones de diseño y lineamientos de operación.

---

### 📊 **Repositorio de Observabilidad**

- **`microservice-app-prometheus`**  
  Contiene configuraciones base para usar **Prometheus** como stack de monitoreo.

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
