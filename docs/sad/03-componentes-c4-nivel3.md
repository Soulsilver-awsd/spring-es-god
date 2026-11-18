# 3. Vista de Componentes y Código (C4 · Niveles 3 y 4)

**Documentos relacionados:** [Índice del SAD](README.md) · [Nivel 2: Contenedores](02-contenedores-c4-nivel2.md) · [Vistas Dinámicas](04-vistas-dinamicas-y-estados.md) · [Modelo de Datos](../srs/05-interfaces-y-datos/02-modelo-datos-esquemas.md)

---

## 1. Vista de Componentes de `api-gateway` (C4 Nivel 3)

```mermaid
flowchart LR
    Req["Peticion HTTP :8080"]

    subgraph GW["[Container] api-gateway"]
        Routes["[Component] RouteLocator\nMapea /api/cuentas/**, /api/transacciones/**\ny rewrite /api/*/db/{segment} -> /api/db/{segment}"]
        Trace["[Component] GatewayTraceGlobalFilter\nInyecta header X-Gateway-Handled: api-gateway"]
        LB["[Component] LoadBalancerFilter\nResuelve lb://ms-cuentas y lb://ms-transacciones\ncontra cache local de Eureka"]
        Routes --> Trace --> LB
    end

    EU["[Container] eureka-server"]
    MS["[Containers] ms-cuentas / ms-transacciones"]

    Req --> Routes
    LB -. "Refresco de instancias" .-> EU
    LB -- "HTTP reenviado" --> MS
```

### Rutas lógicas configuradas
- `/api/cuentas/db/{segment}` → `lb://ms-cuentas` con filtro `SetPath=/api/db/{segment}`
- `/api/cuentas/**` → `lb://ms-cuentas`
- `/api/transacciones/db/{segment}` → `lb://ms-transacciones` con filtro `SetPath=/api/db/{segment}`
- `/api/transacciones/**` → `lb://ms-transacciones`

---

## 2. Vista de Componentes de `ms-cuentas` (C4 Nivel 3)

```mermaid
flowchart TB
    GW["[Container] api-gateway o ms-transacciones"]

    subgraph MSCuentas["[Container] ms-cuentas (x2 instancias)"]
        Ctrl["[Component] CuentaController\nGET /{celular}, /contactos, /saldo-critico,\n/instancia | POST /movimiento-interno, /"]
        DbCtrl["[Component] DbEstadoController\nGET /api/db/estado"]
        Svc["[Component] MovimientoCuentaService\nValida ACTIVA, saldo >= monto, limite diario\ny ejecuta bloqueo deterministico ordenado"]
        Repo["[Component] CuentaRepository y ContactoRepository\nSpring Data JPA sobre cuentas_db"]
        CP["[Component] common-persistence\nAOP @UsarNodo + CustomRoutingDataSource\n+ ReplicaHealthTracker + DbAuditor"]

        Ctrl --> Svc
        Svc --> Repo
        Ctrl --> CP
        Svc --> CP
        DbCtrl --> CP
        Repo --> CP
    end

    PG["[Databases] PostgreSQL Primary / Replica 1 / Replica 2\n(esquema cuentas_db)"]

    GW --> Ctrl
    GW --> DbCtrl
    CP --> PG
```

---

## 3. Vista de Componentes de `ms-transacciones` (C4 Nivel 3)

```mermaid
flowchart TB
    GW["[Container] api-gateway"]

    subgraph MSTrx["[Container] ms-transacciones"]
        Ctrl["[Component] TransaccionController\nPOST /transferir | GET /historial/{celular}\nGET /comprobante/{codigo}"]
        DbCtrl["[Component] DbEstadoController\nGET /api/db/estado"]
        Orch["[Component] TransferenciaOrchestratorService\nGenera codigo TX-2026-XXXX,\ncoordina debito/credito y persiste ledger"]
        Client["[Component] CuentasHttpClient\nRestClient @LoadBalanced hacia\nhttp://ms-cuentas/api/cuentas/movimiento-interno"]
        Repo["[Component] TransaccionRepository\nSpring Data JPA sobre tx_db"]
        CP["[Component] common-persistence\nAOP @UsarNodo + CustomRoutingDataSource\n+ ReplicaHealthTracker + DbAuditor"]

        Ctrl --> Orch
        Ctrl --> Repo
        Orch --> Client
        Orch --> Repo
        DbCtrl --> CP
        Orch --> CP
        Repo --> CP
    end

    CTA["[Containers] ms-cuentas-1 / ms-cuentas-2"]
    PG["[Databases] PostgreSQL Primary / Replica 1 / Replica 2\n(esquema tx_db)"]

    GW --> Ctrl
    GW --> DbCtrl
    Client -- "HTTP lb://ms-cuentas" --> CTA
    CP --> PG
```

---

## 4. Vista de Componentes y Código de `common-persistence` (C4 Niveles 3 y 4)

`common-persistence` es el módulo Maven compartido que encapsula toda la complejidad de CQRS ligero, enrutamiento JDBC, detección de fallos y auditoría real de nodo PostgreSQL.

### Diagrama de Clases (C4 Nivel 4)

```mermaid
classDiagram
    class UsarNodo {
        <<annotation>>
        +TipoNodo value()
    }

    class TipoNodo {
        <<enumeration>>
        PRIMARY
        REPLICA
    }

    class DbKey {
        <<enumeration>>
        PRIMARY
        REPLICA_1
        REPLICA_2
    }

    class PoliticaEnrutamiento {
        <<enumeration>>
        ESCRITURA_DIRECTA
        LECTURA_CRITICA_PRIMARIO
        ROUND_ROBIN_REPLICA
        FAILOVER_REPLICA
    }

    class DbContextHolder {
        -ThreadLocal~DbKey~ CONTEXT
        -ThreadLocal~PoliticaEnrutamiento~ POLICY
        -ThreadLocal~Boolean~ FALLBACK_USED
        +set(DbKey, PoliticaEnrutamiento) void
        +getDbKey() DbKey
        +markFallbackUsed() void
        +clear() void
    }

    class DbRoutingAspect {
        <<Aspect Order HIGHEST_PRECEDENCE>>
        -ReplicaHealthTracker healthTracker
        +routeAndExecute(ProceedingJoinPoint, UsarNodo) Object
        -isCriticalHeaderPresent() boolean
        -executeWithReplicaFailover(ProceedingJoinPoint) Object
    }

    class CustomRoutingDataSource {
        <<AbstractRoutingDataSource>>
        #determineCurrentLookupKey() Object
    }

    class ReplicaHealthTracker {
        -Map~DbKey, DataSource~ replicaDataSources
        -Map~DbKey, ReplicaStatus~ statuses
        -AtomicInteger roundRobinCounter
        -int recoverySuccessThreshold = 2
        +selectNextHealthyReplica() Optional~DbKey~
        +selectAlternativeHealthyReplica(DbKey failed) Optional~DbKey~
        +markUnhealthy(DbKey, String reason) void
        +probeReplicas() void
        +getSnapshot() DbEstadoSnapshot
    }

    class DbAuditor {
        -JdbcTemplate jdbcTemplate
        +capturarAuditoriaActual() AuditoriaDbInfo
    }

    UsarNodo --> TipoNodo
    DbRoutingAspect ..> UsarNodo : intercepta
    DbRoutingAspect --> ReplicaHealthTracker : solicita nodo sano
    DbRoutingAspect --> DbContextHolder : fija clave pre-TX
    CustomRoutingDataSource --> DbContextHolder : lee clave actual
    ReplicaHealthTracker --> DbKey : administra
    DbContextHolder --> DbKey
    DbContextHolder --> PoliticaEnrutamiento
    DbAuditor ..> CustomRoutingDataSource : consulta inet_server_addr y pg_is_in_recovery
```

### Invariantes de diseño en `common-persistence`
1. **Precedencia estricta de AOP:** `DbRoutingAspect` lleva `@Order(Ordered.HIGHEST_PRECEDENCE)` para ejecutarse **antes** de `TransactionInterceptor` (`@Transactional`).
2. **Desactivación de OSIV:** `spring.jpa.open-in-view=false` en ambos microservicios para impedir que el *EntityManager* tome una conexión desde `PRIMARY` antes de entrar a la capa de servicio anotada con `@UsarNodo`.
3. **Limpieza garantizada:** `DbContextHolder.clear()` se ejecuta siempre en un bloque `finally` dentro de `DbRoutingAspect` para evitar contaminación entre hilos reutilizados del pool servlet.
4. **Auditoría real por conexión:** `DbAuditor` ejecuta `SELECT inet_server_addr()::text, inet_server_port(), pg_is_in_recovery()` dentro del mismo contexto de enrutamiento de la operación para construir `auditoriaTecnica` y los encabezados `X-Db-Node` / `X-Db-Fallback`.
