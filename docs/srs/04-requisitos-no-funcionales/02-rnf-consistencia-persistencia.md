# 4.2 Requisitos No Funcionales — Consistencia y Persistencia Replicada

---

### `RNF-05` · Enrutamiento Explícito de Escrituras y Lecturas (No solo `readOnly`)
- **Prioridad:** Crítica
- **Descripción:** La separación de tráfico hacia `PRIMARY`, `REPLICA_1` y `REPLICA_2` debe implementarse mediante un enrutador real de fuentes de datos (`CustomRoutingDataSource extends AbstractRoutingDataSource`) con tres pools `HikariDataSource` independientes.
- **Restricciones técnicas de diseño:**
  1. El aspecto AOP `DbRoutingAspect` debe ejecutarse con `@Order(Ordered.HIGHEST_PRECEDENCE)`, **antes** de `TransactionInterceptor`, garantizando que `DbContextHolder` fije la clave del nodo antes de adquirir la conexión JDBC.
  2. `spring.jpa.open-in-view` debe configurarse en `false` para impedir que Hibernate tome una conexión por defecto al iniciar el request HTTP.
  3. Toda escritura (`POST`, `PUT`, `PATCH`, `DELETE`) se anota con `@UsarNodo(TipoNodo.PRIMARY)`.

---

### `RNF-06` · Consistencia Fuerte Inmediata tras Escritura (*Read-Your-Own-Writes*)
- **Prioridad:** Crítica
- **Descripción:** Las consultas críticas posteriores a una transferencia financiera (`GET /api/cuentas/{celular}/saldo-critico` y `GET /api/transacciones/comprobante/{codigo}`), así como cualquier lectura ordinaria acompañada del encabezado `X-Consistencia: CRITICA`, deben enrutarse obligatoriamente a `postgres-primary`.
- **Justificación Fintech (P07):** En replicación WAL asíncrona (`sync_state = async`), existe una latencia entre el `COMMIT` en el Primario y la aplicación del WAL en las réplicas. Forzar `PRIMARY` en la lectura inmediata post-transferencia garantiza que el cliente jamás visualice un saldo desactualizado ni cometa *double-spending* percibido.

---

### `RNF-07` · Distribución Equilibrada de Lecturas Ordinarias
- **Prioridad:** Alta
- **Descripción:** Las lecturas ordinarias (`GET /api/cuentas/{celular}`, `GET /api/cuentas/{celular}/contactos`, `GET /api/transacciones/historial/{celular}`) deben alternarse de forma equitativa entre las réplicas disponibles mediante una política **Round-Robin** basada en `AtomicInteger`.
- **Métrica de verificación (P05):** Con ambas réplicas sanas, el conteo de consultas atendidas en `/api/db/estado` debe distribuirse ~`50%` en `REPLICA_1` y ~`50%` en `REPLICA_2`, con `pg_is_in_recovery() == true`.

---

### `RNF-08` · Aislamiento Estricto de Esquemas e Integridad WAL
- **Prioridad:** Crítica
- **Descripción:**
  - `ms-cuentas` solo posee credenciales y acceso sobre el esquema `cuentas_db` (`cuentas_user`).
  - `ms-transacciones` solo posee credenciales y acceso sobre el esquema `tx_db` (`tx_user`).
  - Las réplicas PostgreSQL operan con `wal_level=replica`, `max_wal_senders=10`, `wal_keep_size=256MB` y `hot_standby=on`, garantizando conservación de WAL suficientes ante interrupciones temporales breves de una réplica y rechazo de escrituras accidentales en réplicas (`cannot execute INSERT/UPDATE in a read-only transaction`).
