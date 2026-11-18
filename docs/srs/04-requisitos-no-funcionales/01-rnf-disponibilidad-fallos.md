# 4.1 Requisitos No Funcionales — Disponibilidad y Tolerancia a Fallos

---

### `RNF-01` · Balanceo Equitativo entre Múltiples Instancias de `ms-cuentas`
- **Prioridad:** Crítica
- **Descripción:** Ante una carga sostenida de al menos `100` solicitudes HTTP consecutivas contra `ms-cuentas` a través del Gateway, Spring Cloud LoadBalancer debe repartir el tráfico entre `ms-cuentas-1` y `ms-cuentas-2` sin errores bajo condiciones normales.
- **Métrica de verificación (P02):** Distribución cercana a `50% / 50%` (tolerancia esperada de balanceo *Round-Robin* `>= 40%` por instancia) y `100%` de respuestas `HTTP 200 OK`.

---

### `RNF-02` · Continuidad ante Fallo de Instancia de Microservicio
- **Prioridad:** Crítica
- **Descripción:** Si una de las dos instancias de `ms-cuentas` se detiene mientras el sistema recibe solicitudes, Eureka y Spring Cloud LoadBalancer deben converger hacia la instancia sobreviviente sin requerir reinicio manual del Gateway ni de `ms-transacciones`.
- **Parámetros de convergencia:**
  - *Heartbeat* cliente: `5s` (`lease-renewal-interval-in-seconds: 5`).
  - Expiración de *lease*: `12s` (`lease-expiration-duration-in-seconds: 12`).
  - Refresco de caché en clientes/LoadBalancer: `5s` / `3s`.
- **Comportamiento esperado (P03):**
  - En parada controlada (`docker compose stop`), la desinscripción ocurre al apagar la JVM y las peticiones convergen en `~3–6s`.
  - Pueden observarse errores HTTP `503`/`500` transitorios únicamente durante la ventana de refresco de caché si ocurre una caída abrupta; una vez actualizado el registro, el `100%` de las peticiones posteriores debe tener éxito sobre la instancia activa.

---

### `RNF-03` · Tolerancia a Fallos de Réplica PostgreSQL sin Interrupción de Lecturas
- **Prioridad:** Crítica
- **Descripción:** La caída de una de las dos réplicas (`replica1` o `replica2`) no debe interrumpir las consultas ordinarias mientras la otra réplica permanezca saludable.
- **Mecanismo exigido:**
  1. **Detección proactiva:** Sondeo `@Scheduled(fixedDelay = 3000)` con `connectionTimeout = 2000ms` y `queryTimeout = 2s`.
  2. **Failover pasivo en caliente:** Si una lectura falla con `TransactionException` o `DataAccessException` justo antes del siguiente sondeo, `DbRoutingAspect` marca la réplica fallida como no disponible y reintenta de inmediato la misma solicitud sobre la otra réplica saludable (o sobre `PRIMARY` si ambas réplicas cayeron).
- **Métrica de verificación (P06):** `0` errores visibles para el cliente en consultas `GET` tras detener `replica1`.

---

### `RNF-04` · Reincorporación Segura de Réplica Recuperada
- **Prioridad:** Crítica
- **Descripción:** Al reiniciar una réplica previamente detenida, el sistema no debe enviarla de vuelta al balanceo *Round-Robin* por el mero hecho de abrir el puerto TCP `5432`; debe comprobar que PostgreSQL esté aceptando consultas en modo *standby*.
- **Criterio de aptitud (P08):**
  - El monitor ejecuta `SELECT pg_is_in_recovery(), COALESCE(pg_last_wal_replay_lsn()::text, 'none')`.
  - Requiere que `pg_is_in_recovery() == true` y que se superen **2 sondeos consecutivos exitosos** (`recoverySuccessThreshold = 2`) antes de reactivar la réplica en el pool de lecturas.
