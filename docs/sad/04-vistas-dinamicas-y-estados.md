# 4. Vistas Dinámicas, Concurrencia y Estados

**Documentos relacionados:** [Índice del SAD](README.md) · [Componentes Nivel 3 y 4](03-componentes-c4-nivel3.md) · [Flujos de Secuencia en SRS](../srs/05-interfaces-y-datos/03-flujos-secuencia.md) · [Criterios P01–P08](../srs/06-verificacion-y-trazabilidad/01-criterios-aceptacion-p01-p08.md)

---

## 1. Vista Dinámica — Interceptación AOP Pre-Transaccional

Este flujo explica el mecanismo interno que evita que Spring/Hibernate adquiera una conexión JDBC antes de seleccionar el nodo correcto (`PRIMARY`, `REPLICA_1` o `REPLICA_2`).

```mermaid
sequenceDiagram
    autonumber
    participant HTTP as Servlet / Controller
    participant AOP as DbRoutingAspect (HIGHEST_PRECEDENCE)
    participant TRK as ReplicaHealthTracker
    participant CTX as DbContextHolder (ThreadLocal)
    participant TX as TransactionInterceptor (@Transactional)
    participant RDS as CustomRoutingDataSource
    participant PG as PostgreSQL (Primary o Replica)

    HTTP->>AOP: Invoca metodo de servicio @UsarNodo(...)
    alt @UsarNodo(PRIMARY) o Header X-Consistencia: CRITICA
        AOP->>CTX: set(PRIMARY, LECTURA_CRITICA_PRIMARIO / ESCRITURA)
    else @UsarNodo(REPLICA) sin cabecera critica
        AOP->>TRK: selectNextHealthyReplica()
        TRK-->>AOP: REPLICA_1 o REPLICA_2 (Round-Robin AtomicInteger)
        AOP->>CTX: set(REPLICA_X, ROUND_ROBIN_REPLICA)
    end

    AOP->>TX: proceed() entra a frontera @Transactional
    TX->>RDS: Solicita Connection al iniciar transaccion
    RDS->>CTX: determineCurrentLookupKey()
    CTX-->>RDS: Retorna clave fijada (ej. REPLICA_2)
    RDS->>PG: Toma conexion del HikariPool correspondiente

    Note over TX,PG: Si ocurre DataAccessException en REPLICA_X, AOP marca unhealthy y reintenta en otra replica o PRIMARY

    TX-->>AOP: Retorna resultado y cierra transaccion
    AOP->>CTX: finally -> clear()
    AOP-->>HTTP: Respuesta + headers X-Db-Node y X-Db-Fallback
```

---

## 2. Vista Dinámica — Transferencia P2P (`P04`) y Consistencia RYOW (`P07`)

```mermaid
sequenceDiagram
    autonumber
    actor U as Cliente Billetera
    participant GW as api-gateway :8080
    participant TRX as ms-transacciones :8083
    participant CTA as ms-cuentas (#1 o #2)
    participant PGP as PostgreSQL Primary :5432
    participant PGR as Replica 1 / Replica 2

    U->>GW: POST /api/transacciones/transferir
    GW->>TRX: lb://ms-transacciones
    TRX->>CTA: POST http://ms-cuentas/api/cuentas/movimiento-interno
    Note over CTA,PGP: Bloqueo deterministico por celular ascendente evita deadlocks en transferencias cruzadas
    CTA->>PGP: BEGIN TX -> Validar estado, saldo, limite -> UPDATE ambos saldos -> COMMIT
    PGP-->>CTA: Saldos actualizados
    CTA-->>TRX: 200 OK (nuevoSaldoOrigen, instanciaCuentasConsultada)
    TRX->>PGP: INSERT INTO tx_db.transacciones (estado = EXITOSA)
    PGP-->>TRX: Comprobante TX-2026-XXXX confirmado
    TRX-->>GW: 201 Created + ApiResponse con auditoriaTecnica
    GW-->>U: 201 Created (X-Gateway-Handled: api-gateway)

    Note over U,PGR: Lectura critica inmediata (Read-Your-Own-Writes)
    U->>GW: GET /api/cuentas/{origen}/saldo-critico
    GW->>CTA: lb://ms-cuentas
    CTA->>PGP: SELECT saldo (forzado a PRIMARY por @UsarNodo(PRIMARY))
    PGP-->>CTA: Saldo exacto post-transferencia (recovery=false)
    CTA-->>U: 200 OK (politicaEnrutamiento = LECTURA_CRITICA_PRIMARIO)

    Note over U,PGR: Lectura ordinaria tolerante a lag WAL breve
    U->>GW: GET /api/transacciones/historial/{origen}
    GW->>TRX: lb://ms-transacciones
    TRX->>PGR: SELECT historial (Round-Robin REPLICA_1 / REPLICA_2)
    PGR-->>TRX: Historial (recovery=true)
    TRX-->>U: 200 OK (politicaEnrutamiento = ROUND_ROBIN_REPLICA)
```

---

## 3. Máquina de Estados — Ciclo de Salud de Réplicas (`ReplicaHealthTracker`)

Para cumplir con `RNF-03` y `RNF-04` (`P06` y `P08`), cada réplica (`REPLICA_1`, `REPLICA_2`) sigue una máquina de estados finita administrada por `ReplicaHealthTracker`:

```mermaid
stateDiagram-v2
    [*] --> HEALTHY : Arranque inicial si sondeo OK (recovery=true)
    [*] --> UNHEALTHY : Arranque si replica no disponible

    HEALTHY --> UNHEALTHY : Fallo en sondeo @Scheduled (3s)\no DataAccessException en lectura
    UNHEALTHY --> RECOVERING : Sondeo exitoso (1/2)\npg_is_in_recovery() == true
    RECOVERING --> HEALTHY : Segundo sondeo consecutivo exitoso (2/2)\nReincorporada al Round-Robin
    RECOVERING --> UNHEALTHY : Falla el segundo sondeo\n(reinicia contador a 0)
```

### Reglas de transición y *Failover*
1. **Degradación inmediata (`HEALTHY -> UNHEALTHY`):** Puede dispararse de forma **proactiva** por el sondeo `@Scheduled(fixedDelay = 3000)` (`connectionTimeout = 2000ms`, `queryTimeout = 2s`) o de forma **reactiva** dentro de `DbRoutingAspect` si una consulta real falla antes del siguiente ciclo de sondeo.
2. **Rescate en la misma petición (*Failover pasivo*):** Cuando `DbRoutingAspect` captura `DataAccessException` o `TransactionException` en una lectura dirigida a `REPLICA_X`, marca `REPLICA_X` como `UNHEALTHY`, selecciona la réplica alternativa sana (o `PRIMARY` si ambas réplicas están caídas), marca `X-Db-Fallback: true` y reintenta la operación de lectura de manera transparente para el cliente.
3. **Reincorporación segura (`UNHEALTHY -> RECOVERING -> HEALTHY`):** Se exige que PostgreSQL responda a SQL (`pg_is_in_recovery() == true` y reporte `pg_last_wal_replay_lsn()`) durante **2 sondeos consecutivos** (`recoverySuccessThreshold = 2`), evitando enviar tráfico a una réplica que apenas abrió su socket TCP mientras termina de iniciar o recuperar WAL.

---

## 4. Concurrencia y Prevención de *Deadlocks* en `ms-cuentas`

Cuando dos usuarios ejecutan transferencias simultáneas opuestas (`A -> B` y `B -> A`), adquirir bloqueos `SELECT ... FOR UPDATE` en orden distinto produciría un interbloqueo (*deadlock*) en PostgreSQL.

**Estrategia arquitectónica en `MovimientoCuentaService`:**
- Antes de bloquear filas en `cuentas_db.cuentas`, los identificadores `celularOrigen` y `celularDestino` se ordenan lexicográficamente (`menor`, `mayor`).
- La transacción adquiere el bloqueo pesimista siempre primero sobre `menor` y luego sobre `mayor`, garantizando un orden global acíclico de locks dentro de `PRIMARY`.
- Al ejecutarse sobre `PRIMARY` bajo `@Transactional`, se mantiene la atomicidad ACID sin necesidad de coordinadores distribuidos 2PC/XA entre microservicios.
