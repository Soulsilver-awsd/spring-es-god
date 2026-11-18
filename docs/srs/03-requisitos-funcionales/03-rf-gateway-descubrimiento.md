# 3.3 Requisitos Funcionales — Descubrimiento y Puerta de Enlace (`eureka-server` y `api-gateway`)

---

### `RF-10` · Registro Dinámico y Detección de Instancias en Eureka Server
- **Prioridad:** Crítica
- **Servicio propietario:** `eureka-server` (`:8761`) + clientes Eureka
- **Descripción:** Todas las instancias de `ms-cuentas` (`ms-cuentas-1`, `ms-cuentas-2`), `ms-transacciones` y `api-gateway` deben registrarse automáticamente en Eureka Server al arrancar, manteniendo su estado mediante *heartbeats* periódicos.
- **Criterios de aceptación:**
  1. `GET http://localhost:8761/eureka/apps` lista `MS-CUENTAS` con 2 instancias activas en estado `UP` y `MS-TRANSACCIONES` con 1 instancia en estado `UP`.
  2. Al detener una instancia (`docker compose stop ms-cuentas-2`), Eureka la elimina del registro activo (`DELETE` en apagado limpio o expiración de *lease* tras caída abrupta).
  3. Al reiniciar la instancia, vuelve a aparecer automáticamente en estado `UP`.

---

### `RF-11` · Enrutamiento HTTP Basado en Nombres Lógicos en API Gateway
- **Prioridad:** Crítica
- **Servicio propietario:** `api-gateway` (`:8080`)
- **Descripción:** Todas las peticiones externas deben ingresar por `api-gateway`, el cual resolverá dinámicamente el destino mediante URIs `lb://ms-cuentas` y `lb://ms-transacciones` apoyado en **Spring Cloud LoadBalancer**.
- **Tabla de rutas:**
  - `/api/cuentas/db/{segment}` → `lb://ms-cuentas` (`SetPath=/api/db/{segment}`)
  - `/api/cuentas/**` → `lb://ms-cuentas`
  - `/api/transacciones/db/{segment}` → `lb://ms-transacciones` (`SetPath=/api/db/{segment}`)
  - `/api/transacciones/**` → `lb://ms-transacciones`
- **Criterios de aceptación:**
  1. Ninguna ruta en `application.yml` contiene IPs ni puertos fijos hacia los microservicios de negocio.
  2. En ráfagas de 100+ solicitudes hacia `GET /api/cuentas/{celular}` (P02), el Gateway distribuye el tráfico entre `ms-cuentas-1` y `ms-cuentas-2`.
  3. Toda respuesta agrega el encabezado `X-Gateway-Handled: api-gateway`.

---

### `RF-12` · Envoltorio Estándar de Respuesta y Auditoría Técnica (`ApiResponse<T>`)
- **Prioridad:** Alta
- **Servicio propietario:** `common-persistence`, `ms-cuentas`, `ms-transacciones`
- **Descripción:** Todas las respuestas de negocio deben retornar un envoltorio uniforme `ApiResponse<T>` con `estado`, `mensaje`, `datos` y `auditoriaTecnica`.
- **Campos obligatorios de `auditoriaTecnica`:**
  - `servicioOrigen`: nombre e instancia que emite la respuesta (ej. `ms-transacciones:8083` o `ms-cuentas-1:8081`).
  - `instanciaCuentasConsultada`: cuando aplique en transferencias, instancia exacta de `ms-cuentas` que ejecutó el débito/crédito.
  - `nodoBaseDatos`: nombre lógico (`PRIMARY` / `REPLICA_1` / `REPLICA_2`), IP real obtenida vía `SELECT inet_server_addr()`, puerto y valor real de `pg_is_in_recovery()`.
  - `politicaEnrutamiento`: `ESCRITURA_DIRECTA`, `LECTURA_CRITICA_PRIMARIO`, `ROUND_ROBIN_REPLICA` o `FAILOVER_REPLICA`.
- **Criterios de aceptación:**
  1. Los valores de IP y `pg_is_in_recovery()` provienen de la conexión JDBC real utilizada en la transacción, nunca de cadenas estáticas simuladas.
