# 5.3 Flujos de Secuencia Críticos

## 1. Transferencia P2P Inter-Servicios (P04) y Lectura Crítica Inmediata (P07)

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario Billetera
    participant GW as API Gateway (:8080)
    participant TRX as ms-transacciones (:8083)
    participant EU as Eureka Server (:8761)
    participant CTA as ms-cuentas (#1 o #2)
    participant PGP as PostgreSQL Primary (:5432)
    participant PGR as Replica 1 / Replica 2

    Note over U,PGR: P04 - Flujo de transferencia P2P
    U->>GW: POST /api/transacciones/transferir {origen, destino, monto}
    GW->>TRX: Enruta via lb://ms-transacciones
    TRX->>EU: Consulta instancias activas de ms-cuentas
    TRX->>CTA: POST http://ms-cuentas/api/cuentas/movimiento-interno
    CTA->>PGP: BEGIN TX + Validar estado, saldo >= monto, limite_diario
    PGP-->>CTA: Debito origen y credito destino confirmados
    CTA-->>TRX: 200 OK (nuevoSaldoOrigen + instanciaCuentas)
    TRX->>PGP: INSERT INTO tx_db.transacciones (estado = EXITOSA)
    PGP-->>TRX: Comprobante TX-2026-XXXX persistido
    TRX-->>GW: 201 Created + ApiResponse con auditoriaTecnica
    GW-->>U: 201 Created

    Note over U,PGR: P07 - Lectura critica inmediata post-transferencia (Read-Your-Own-Writes)
    U->>GW: GET /api/cuentas/{origen}/saldo-critico
    GW->>CTA: Enruta via lb://ms-cuentas
    CTA->>PGP: SELECT saldo FROM cuentas_db.cuentas (forzado a PRIMARY)
    PGP-->>CTA: Saldo actualizado sin lag WAL (recovery=false)
    CTA-->>U: 200 OK (politicaEnrutamiento = LECTURA_CRITICA_PRIMARIO)

    Note over U,PGR: P05 - Lectura ordinaria de historial en replicas
    U->>GW: GET /api/transacciones/historial/{origen}
    GW->>TRX: lb://ms-transacciones
    TRX->>PGR: SELECT en REPLICA_1 o REPLICA_2 (Round-Robin)
    PGR-->>TRX: Historial (recovery=true)
    TRX-->>U: 200 OK
```

---

## 2. Tolerancia a Fallos y Reincorporación Segura de Réplica (P06 y P08)

```mermaid
sequenceDiagram
    autonumber
    participant MON as ReplicaHealthTracker (@Scheduled 3s)
    participant ASP as DbRoutingAspect (AOP)
    participant R1 as PostgreSQL Replica 1 (:5433)
    participant R2 as PostgreSQL Replica 2 (:5434)

    Note over MON,R2: Estado normal - Round-Robin 50% / 50%
    ASP->>R1: Lectura #1 (REPLICA_1)
    ASP->>R2: Lectura #2 (REPLICA_2)

    Note over R1: P06 - Simulacion de caida (docker compose stop replica1)
    ASP->>R1: Lectura #3 intenta conectar (o sondeo detecta fallo)
    R1--xASP: Error de conexion (timeout 2s)
    ASP->>MON: markUnhealthy(REPLICA_1)
    ASP->>R2: Failover transparente en la misma solicitud
    R2-->>ASP: 200 OK (X-Db-Fallback=true)

    Note over ASP,R2: Mientras REPLICA_1 siga caida, 100% de lecturas van a REPLICA_2
    ASP->>R2: Lecturas #4, #5, #6...

    Note over R1: P08 - Reinicio (docker compose start replica1)
    MON->>R1: Sondeo #1: SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn()
    R1-->>MON: true (aun en periodo de validacion 1/2)
    MON->>R1: Sondeo #2: SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn()
    R1-->>MON: true (umbral 2/2 alcanzado -> REINCORPORADA)
    ASP->>R1: Vuelve a participar en el Round-Robin
```
