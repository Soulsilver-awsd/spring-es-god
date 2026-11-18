# 4.3 Requisitos No Funcionales — Seguridad, Reproducibilidad y Observabilidad

---

### `RNF-09` · Gestión Segura de Credenciales y Secretos
- **Prioridad:** Crítica
- **Descripción:** Ningún archivo versionado en Git (`docker-compose.yml`, `application.yml`, scripts `.sh`, documentación) debe contener contraseñas reales de producción ni secretos fijos no parametrizados.
- **Criterios de cumplimiento:**
  1. Existencia de `.env.example` con valores plantilla claramente identificables (`CAMBIAR_...`).
  2. Inclusión de `.env` en `.gitignore`.
  3. Inyección de credenciales hacia contenedores Spring Boot y PostgreSQL exclusivamente mediante variables de entorno (`${...}`).

---

### `RNF-10` · Reproducibilidad Total del Entorno
- **Prioridad:** Crítica
- **Descripción:** Cualquier integrante o evaluador debe poder compilar, desplegar y probar el sistema completo en una máquina limpia siguiendo únicamente los pasos del `README.md`, sin depender de herramientas preinstaladas en el host distintas de Docker y Docker Compose (la compilación Java/Maven ocurre dentro de `Dockerfile` multi-etapa).
- **Criterios de cumplimiento:**
  1. Orden de arranque gobernado por `depends_on` y `healthcheck` (`primary` sano → `replica1`/`replica2`; `eureka-server` sano → microservicios y `api-gateway`).
  2. Inicialización idempotente de esquemas y datos semilla en el Primario (protegida con *advisory lock* de PostgreSQL para evitar condiciones de carrera entre `ms-cuentas-1` y `ms-cuentas-2`).

---

### `RNF-11` · Trazabilidad y Observabilidad en Tiempo Real
- **Prioridad:** Alta
- **Descripción:** Cada respuesta HTTP del sistema debe permitir identificar sin ambigüedad:
  - Qué instancia de microservicio respondió (`X-Service-Instance` + `auditoriaTecnica.servicioOrigen`).
  - Qué instancia atendió la llamada interna inter-servicios (`auditoriaTecnica.instanciaCuentasConsultada`).
  - Qué nodo PostgreSQL real ejecutó la sentencia SQL (`X-Db-Node` + `auditoriaTecnica.nodoBaseDatos` con `inet_server_addr()` y `pg_is_in_recovery()`).
  - Si ocurrió *failover* automático de réplica (`X-Db-Fallback: true`).

---

### `RNF-12` · Mantenibilidad y Portabilidad Documental
- **Prioridad:** Media
- **Descripción:** Toda la documentación, colecciones de pruebas y scripts de verificación deben vivir versionados dentro del repositorio (`README.md`, `docs/srs/`, `docs/`) sin enlaces rotos ni dependencias propietarias cerradas.
