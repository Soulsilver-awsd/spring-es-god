# 2.1 Perspectiva del Producto y Topología

## 1. Contexto Arquitectónico

El sistema opera como una arquitectura de microservicios autocontenida en contenedores Docker interconectados por una red privada, exponiendo un único punto de entrada HTTP para clientes (`api-gateway:8080`) y un tablero de descubrimiento (`eureka-server:8761`).

```mermaid
flowchart TB
    Client["Cliente / App Billetera / Postman / Script P02"]

    subgraph Edge["Capa de Entrada y Descubrimiento"]
        GW["Spring Cloud Gateway :8080\nlb://ms-cuentas | lb://ms-transacciones"]
        EU["Eureka Server :8761\nRegistro Dinámico de Instancias"]
        GW -. "Consulta registro" .-> EU
    end

    subgraph Microservices["Microservicios de Negocio (Spring Boot)"]
        CTA1["ms-cuentas (Instancia 1) :8081\nEsquema privado: cuentas_db.*"]
        CTA2["ms-cuentas (Instancia 2) :8082\nEsquema privado: cuentas_db.*"]
        TRX["ms-transacciones :8083\nEsquema privado: tx_db.*"]

        TRX -- "HTTP @LoadBalanced\nhttp://ms-cuentas/api/cuentas/movimiento-interno" --> CTA1
        TRX -- "Balanceo dinámico" --> CTA2
        CTA1 -. "Heartbeat 5s" .-> EU
        CTA2 -. "Heartbeat 5s" .-> EU
        TRX -. "Heartbeat 5s" .-> EU
    end

    subgraph Persistence["Enrutamiento de Persistencia + PostgreSQL 17"]
        ROUTER["CustomRoutingDataSource\n(AbstractRoutingDataSource + DbContextHolder)"]
        PGP[("PostgreSQL Primary :5432\nRead / Write + Lectura Crítica")]
        PGR1[("PostgreSQL Replica 1 :5433\nRead Only (Hot Standby)")]
        PGR2[("PostgreSQL Replica 2 :5434\nRead Only (Hot Standby)")]

        CTA1 --> ROUTER
        CTA2 --> ROUTER
        TRX --> ROUTER
        ROUTER -- "POST / PUT / Lectura Crítica" --> PGP
        ROUTER -- "Lecturas Ordinarias (Round-Robin)" --> PGR1
        ROUTER -- "Lecturas Ordinarias (Round-Robin)" --> PGR2
        PGP == "Streaming WAL" ==> PGR1
        PGP == "Streaming WAL" ==> PGR2
    end

    Client --> GW
    GW -- "lb://ms-cuentas" --> CTA1
    GW -- "lb://ms-cuentas" --> CTA2
    GW -- "lb://ms-transacciones" --> TRX
```

---

## 2. Separación de Responsabilidades

1. **Descubrimiento HTTP (`eureka-server` + `Spring Cloud LoadBalancer`):** Administra exclusivamente el ciclo de vida y localización dinámica de los microservicios (`ms-cuentas`, `ms-transacciones`).
2. **Enrutamiento de Base de Datos (`CustomRoutingDataSource` + `ReplicaHealthTracker`):** Administra exclusivamente la selección entre el nodo Primario y las dos Réplicas PostgreSQL. Eureka nunca registra ni balancea nodos de base de datos.
3. **Propiedad de Datos (*Database-per-Service*):** `ms-cuentas` solo define entidades JPA sobre el esquema `cuentas_db` y `ms-transacciones` solo sobre `tx_db`, respaldado por usuarios PostgreSQL con permisos separados.
