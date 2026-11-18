# Documento de Arquitectura de Software (SAD)
## Sistema Distribuido de Billetera Digital y Transferencias P2P (*Fintech*)

**Estándares de referencia:** ISO/IEC/IEEE 42010 · Modelo C4 (Niveles 1–4 + Despliegue) · *Architecture Decision Records* (ADR) · ISO/IEC 25010  
**Versión del documento:** `1.0.0`  
**Fecha:** `2026-11-18`  
**Stack objetivo:** Java 21 LTS · Spring Boot `3.4.3` · Spring Cloud `2024.0.1` (`Eureka`, `Gateway`, `LoadBalancer`) · PostgreSQL `17` (`1` Primario + `2` Réplicas WAL) · Docker Compose  
**Especificación de requisitos asociada:** [SRS Modular IEEE 29148](../srs/README.md) · [SDD Modular (IEEE 1016)](../sdd/README.md)

---

## 1. Propósito del Documento

Mientras el [SRS](../srs/README.md) define **qué** debe hacer el sistema (`RF-01` a `RF-12`, `RNF-01` a `RNF-12` y pruebas `P01–P08`), este **Documento de Arquitectura de Software (SAD)** describe **cómo** está estructurado internamente, **cómo** interactúan sus componentes en tiempo de ejecución y **por qué** se tomaron las decisiones técnicas clave.

---

## 2. Estructura Modular del SAD

| Módulo | Nivel / Vista | Contenido Principal | Documento |
|---|---|---|---|
| **01 · Contexto del Sistema** | C4 Nivel 1 | Actores externos, límites del sistema, exclusiones y restricciones obligatorias | [01-contexto-c4-nivel1.md](01-contexto-c4-nivel1.md) |
| **02 · Contenedores** | C4 Nivel 2 | Los 8 contenedores desplegables, puertos, protocolos, separación Eureka vs. DB y propiedad de esquemas | [02-contenedores-c4-nivel2.md](02-contenedores-c4-nivel2.md) |
| **03 · Componentes y Código** | C4 Niveles 3 y 4 | Descomposición interna de Gateway, `ms-cuentas`, `ms-transacciones` y diagrama de clases de `common-persistence` | [03-componentes-c4-nivel3.md](03-componentes-c4-nivel3.md) |
| **04 · Vistas Dinámicas y Estados** | Comportamiento | Ciclo AOP pre-transaccional, flujo P2P + RYOW, bloqueo anti-*deadlock* y máquina de estados de réplicas | [04-vistas-dinamicas-y-estados.md](04-vistas-dinamicas-y-estados.md) |
| **05 · Despliegue e Infraestructura** | C4 Despliegue | Topología Docker Compose, red privada, orden de arranque (`healthcheck`), WAL físico y seguridad `.env` | [05-despliegue-e-infraestructura.md](05-despliegue-e-infraestructura.md) |
| **06 · Decisiones Arquitectónicas** | ADRs (`001`–`008`) | Contexto, decisión, alternativas descartadas y *trade-offs* de diseño | [06-adrs-decisiones-arquitectonicas.md](06-adrs-decisiones-arquitectonicas.md) |
| **07 · Calidad, Riesgos y Trazabilidad** | ISO 25010 / Matriz | Escenarios de atributos de calidad, riesgos técnicos, mitigaciones y mapeo hacia `P01–P08` | [07-calidad-riesgos-y-trazabilidad.md](07-calidad-riesgos-y-trazabilidad.md) |

---

## 3. Resumen de Drivers Arquitectónicos (*Architectural Drivers*)

| Driver | Origen en SRS | Impacto Directo en la Arquitectura |
|---|---|---|
| **Descubrimiento dinámico sin rutas fijas** | `RF-10`, `RF-11`, `RNF-01`, `RNF-02` | Introducción de `eureka-server` (`:8761`) y enrutamiento `lb://` en `api-gateway` (`:8080`) y `RestClient` `@LoadBalanced` en `ms-transacciones`. |
| **Separación explícita de lecturas/escrituras (CQRS ligero)** | `RNF-05`, `RNF-07` | Módulo compartido `common-persistence` basado en `AbstractRoutingDataSource`, 3 pools `HikariDataSource` y aspecto AOP con `@Order(Ordered.HIGHEST_PRECEDENCE)` + `open-in-view=false`. |
| **Consistencia fuerte post-escritura (*RYOW*)** | `RF-03`, `RF-08`, `RNF-06` | Anotación `@UsarNodo(TipoNodo.PRIMARY)` en consultas críticas (`/saldo-critico`, `/comprobante/{codigo}`) y soporte del encabezado `X-Consistencia: CRITICA`. |
| **Continuidad ante caída y recuperación controlada de réplicas** | `RNF-03`, `RNF-04` | `ReplicaHealthTracker` (`@Scheduled(fixedDelay = 3000)`), *failover* pasivo en caliente desde AOP y reincorporación condicionada a `pg_is_in_recovery() == true` en `2/2` sondeos. |
| **Aislamiento de datos por servicio** | `RNF-08` | Esquemas privados (`cuentas_db` y `tx_db`) y roles PostgreSQL independientes (`cuentas_user`, `tx_user`) sin claves foráneas ni acceso SQL cruzado. |
| **Trazabilidad verificable y reproducibilidad** | `RF-09`, `RF-12`, `RNF-09`–`RNF-12` | Envoltorio `ApiResponse<T>` con consulta real a `inet_server_addr()` y `pg_is_in_recovery()`, credenciales externalizadas en `.env` y compilación multi-etapa en Docker. |
