# 2. Diseño Detallado de `common-persistence`

**Documentos relacionados:** [Índice del SDD](README.md) · [Componentes C4 Nivel 3/4](../sad/03-componentes-c4-nivel3.md) · [Vistas Dinámicas](../sad/04-vistas-dinamicas-y-estados.md) · [Contratos REST](../srs/05-interfaces-y-datos/01-contratos-api-rest.md)

---

## 1. Tipos, Anotaciones y Contexto por Hilo

### Enumeraciones y Anotación
```java
public enum TipoNodo { PRIMARY, REPLICA }

public enum DbKey { PRIMARY, REPLICA_1, REPLICA_2 }

public enum PoliticaEnrutamiento {
    ESCRITURA_DIRECTA,
    LECTURA_CRITICA_PRIMARIO,
    ROUND_ROBIN_REPLICA,
    FAILOVER_REPLICA
}

@Target({ElementType.METHOD, ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
public @interface UsarNodo {
    TipoNodo value();
    boolean escritura() default false;
}
```

### `DbContextHolder`
Mantiene tres `ThreadLocal` sincronizados por petición:
- `CURRENT_NODE`: `DbKey` activo (`PRIMARY`, `REPLICA_1`, `REPLICA_2`).
- `CURRENT_POLICY`: `PoliticaEnrutamiento` aplicada.
- `FALLBACK_USED`: `Boolean` que dispara el header HTTP `X-Db-Fallback: true`.

---

## 2. Configuración de Pools `HikariDataSource` y `CustomRoutingDataSource`

`MultiNodeDataSourceConfig` desactiva el `DataSourceAutoConfiguration` por defecto (o declara `@Primary DataSource`) y construye **tres pools independientes** a partir de `PersistenceRoutingProperties` (`app.db.primary.*`, `app.db.replicas[0].*`, `app.db.replicas[1].*`):

| Propiedad HikariCP | `PRIMARY` | `REPLICA_1` / `REPLICA_2` | Motivo |
|---|---|---|---|
| `connectionTimeout` | `5000` ms | `2000` ms | Detectar rápidamente réplicas caídas (`P06`) sin bloquear hilos HTTP. |
| `validationTimeout` | `2000` ms | `1500` ms | Validación rápida de conexiones del pool. |
| `maximumPoolSize` | `10` | `10` | Capacidad holgada para ráfagas `P02` (`100+` req). |
| `minimumIdle` | `2` | `1` | Menor consumo de conexiones inactivas en réplicas. |
| `readOnly` | `false` | `true` | Refuerza en el driver JDBC la naturaleza de solo lectura de las réplicas. |
| `poolName` | `hikari-primary` | `hikari-replica-1` / `2` | Trazabilidad en logs y métricas Actuator. |

`CustomRoutingDataSource extends AbstractRoutingDataSource`:
- `targetDataSources`: mapa inmutable `{ PRIMARY -> dsPrimary, REPLICA_1 -> dsReplica1, REPLICA_2 -> dsReplica2 }`.
- `defaultTargetDataSource`: `dsPrimary`.
- `determineCurrentLookupKey()`: retorna `Optional.ofNullable(DbContextHolder.getDbKey()).orElse(DbKey.PRIMARY)`.

### Bean `@FlywayDataSource` Dedicado al Primario
`MultiNodeDataSourceConfig` expone además un bean `DataSource` anotado con `@FlywayDataSource` que apunta **directamente a `dsPrimary`**:
- Garantiza que **Flyway** ejecute todas las migraciones versionadas (`V1__`, `V2__`, etc.) y escriba `flyway_schema_history` exclusivamente sobre el nodo **Primario** (`recovery=false`), evitando que intente migrar sobre una réplica *Hot Standby* de solo lectura o dependa de `DbContextHolder` en fase de arranque.
- Los cambios confirmados en `PRIMARY` se propagan automáticamente a `replica1` y `replica2` mediante *streaming WAL*.

---

## 3. Algoritmo Detallado de `DbRoutingAspect`

`DbRoutingAspect` lleva `@Aspect`, `@Component` y `@Order(Ordered.HIGHEST_PRECEDENCE)` para ejecutarse **antes** del `TransactionInterceptor` de Spring.

```text
ALGORITMO routeAndExecute(ProceedingJoinPoint pjp, UsarNodo usarNodo):
1. Leer HttpServletRequest actual desde RequestContextHolder (si existe).
2. Evaluar si existe header "X-Consistencia" igual a "CRITICA" (case-insensitive).
3. SI usarNodo.value() == PRIMARY O headerCritico == true:
   a. politica = usarNodo.escritura() ? ESCRITURA_DIRECTA : LECTURA_CRITICA_PRIMARIO
   b. DbContextHolder.set(DbKey.PRIMARY, politica, false)
   c. Ejecutar pjp.proceed() dentro de try { ... } finally { DbContextHolder.clear() }
4. SI usarNodo.value() == REPLICA Y headerCritico == false:
   a. replicaOpt = replicaHealthTracker.selectNextHealthyReplica()
   b. SI replicaOpt esta vacia (ambas replicas caidas):
      - DbContextHolder.set(DbKey.PRIMARY, FAILOVER_REPLICA, true)
      - Ejecutar pjp.proceed() en try/finally clear()
   c. SI replicaOpt tiene clave k (ej. REPLICA_1):
      - DbContextHolder.set(k, ROUND_ROBIN_REPLICA, false)
      - INTENTAR return pjp.proceed()
      - CAPTURAR (DataAccessException | TransactionException ex):
         i.   replicaHealthTracker.markUnhealthy(k, ex.getMessage())
         ii.  altOpt = replicaHealthTracker.selectAlternativeHealthyReplica(k)
         iii. targetFallback = altOpt.orElse(DbKey.PRIMARY)
         iv.  DbContextHolder.set(targetFallback, FAILOVER_REPLICA, true)
         v.   return pjp.proceed()   // Reintento transparente en la misma solicitud
      - FINALLY: DbContextHolder.clear()
```

---

## 4. Diseño de `ReplicaHealthTracker`

### Estado interno por réplica (`ReplicaStatus`)
- `DbKey key` (`REPLICA_1` / `REPLICA_2`)
- `volatile boolean available`
- `volatile int consecutiveSuccesses` (inicia en `0`)
- `volatile int consecutiveFailures`
- `volatile String lastReplayLsn`
- `volatile Instant lastCheckedAt`
- `volatile String lastError`
- `AtomicLong servedQueries` (más un `AtomicLong primaryServedQueries` global)

### Método de sondeo periódico (`@Scheduled(fixedDelayString = "${app.db.health-check-interval-ms:3000}")`)
1. Para cada réplica (`REPLICA_1`, `REPLICA_2`):
   - Ejecuta con `queryTimeout = 2` segundos sobre su `DataSource` directo (sin pasar por `CustomRoutingDataSource`):
     ```sql
     SELECT pg_is_in_recovery(), COALESCE(pg_last_wal_replay_lsn()::text, 'none');
     ```
   - Si retorna `pg_is_in_recovery() == true`:
     - Incrementa `consecutiveSuccesses`, limpia `lastError` y actualiza `lastReplayLsn`.
     - Si `!available` y `consecutiveSuccesses >= 2` (`recoverySuccessThreshold = 2`), marca `available = true`.
   - Si retorna `false` o lanza `SQLException`:
     - Pone `available = false`, `consecutiveSuccesses = 0`, incrementa `consecutiveFailures` y registra `lastError`.

### Selección *Round-Robin*
`selectNextHealthyReplica()`:
1. Toma la lista ordenada de réplicas con `available == true`.
2. Si está vacía, retorna `Optional.empty()`.
3. Si tiene tamaño `n`, calcula `idx = Math.floorMod(roundRobinCounter.getAndIncrement(), n)` y retorna `healthy.get(idx)`.

---

## 5. Auditoría Real y Envoltorio Estándar (`DbAuditor` + `ApiResponse<T>`)

### Consulta SQL real en `DbAuditor`
Ejecutada dentro de la misma transacción/contexto de nodo para garantizar coherencia con el nodo que sirvió los datos:

```sql
SELECT inet_server_addr()::text AS server_ip,
       inet_server_port()       AS server_port,
       pg_is_in_recovery()      AS in_recovery;
```

### Contrato de `ApiResponse<T>` y `AuditoriaTecnicaDto`
```java
public record AuditoriaTecnicaDto(
    String servicioOrigen,             // ej. "ms-cuentas-1:8081"
    String instanciaCuentasConsultada, // null en ms-cuentas; poblado en ms-transacciones
    String nodoBaseDatos,              // ej. "REPLICA_1 (172.18.0.3:5432, recovery=true)"
    PoliticaEnrutamiento politicaEnrutamiento
) {}

public record ApiResponse<T>(
    String estado,                     // "OK" | "ERROR"
    String mensaje,
    T datos,
    AuditoriaTecnicaDto auditoriaTecnica
) {}
```

### Encabezados HTTP de trazabilidad emitidos por controlador/advice
- `X-Service-Instance`: valor de `${spring.application.name}:${INSTANCE_ID}:${server.port}`
- `X-Db-Node`: clave física (`PRIMARY`, `REPLICA_1` o `REPLICA_2`) + IP real
- `X-Db-Fallback`: `"true"` cuando `politicaEnrutamiento == FAILOVER_REPLICA` (opcionalmente `"false"` en flujo normal)

---

## 6. Endpoint de Diagnóstico `/api/db/estado`

Expuesto automáticamente por `DbEstadoController` en ambos microservicios (accesible vía Gateway como `GET /api/cuentas/db/estado` y `GET /api/transacciones/db/estado` gracias al filtro `SetPath`):

```json
{
  "servicio": "ms-cuentas-1:8081",
  "consultasTotales": {
    "PRIMARY": 4,
    "REPLICA_1": 12,
    "REPLICA_2": 11
  },
  "replicas": [
    {
      "nodo": "REPLICA_1",
      "available": true,
      "consecutiveSuccesses": 18,
      "lastReplayLsn": "0/1A04F80",
      "lastError": null,
      "lastCheckedAt": "2026-11-18T17:55:00Z"
    },
    {
      "nodo": "REPLICA_2",
      "available": true,
      "consecutiveSuccesses": 18,
      "lastReplayLsn": "0/1A04F80",
      "lastError": null,
      "lastCheckedAt": "2026-11-18T17:55:00Z"
    }
  ]
}
```
