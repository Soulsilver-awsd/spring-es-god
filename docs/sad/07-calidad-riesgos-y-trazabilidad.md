# 7. Atributos de Calidad, Riesgos y Trazabilidad

**Documentos relacionados:** [Índice del SAD](README.md) · [ADRs](06-adrs-decisiones-arquitectonicas.md) · [Criterios P01–P08](../srs/06-verificacion-y-trazabilidad/01-criterios-aceptacion-p01-p08.md) · [Matriz de Trazabilidad SRS](../srs/06-verificacion-y-trazabilidad/02-matriz-trazabilidad.md)

---

## 1. Escenarios de Atributos de Calidad (ISO/IEC 25010)

| Atributo | Escenario Arquitectónico | Mecanismo de Diseño | Métrica / Validación |
|---|---|---|---|
| **Disponibilidad y Tolerancia a Fallos** | Caída de una instancia de `ms-cuentas` bajo tráfico continuo | Eureka *heartbeat* `5s`, expiración `12s`, refresco LoadBalancer `3–5s` | Convergencia hacia la instancia sobreviviente (`P03`) |
| **Disponibilidad de Lectura BD** | Caída abrupta o detención de `replica1` (`docker compose stop replica1`) | Sondeo cada `3s` + *failover* pasivo inmediato en `DbRoutingAspect` | `0` errores visibles al cliente en lecturas `GET` (`P06`) |
| **Integridad / Consistencia Financiera** | Consulta de saldo o comprobante justo después de transferir `$25.00` | `@UsarNodo(PRIMARY)` en `/saldo-critico` y `/comprobante/{codigo}` + `X-Consistencia: CRITICA` | `pg_is_in_recovery() == false` y saldo exacto sin *lag* WAL (`P07`) |
| **Escalabilidad Horizontal / Reparto** | Ráfaga de `100+` peticiones HTTP y lecturas ordinarias repetidas | Spring Cloud LoadBalancer (`ms-cuentas` ×2) + Round-Robin `AtomicInteger` (`REPLICA_1`/`REPLICA_2`) | Reparto ~`50/50` en instancias (`P02`) y en réplicas (`P05`) |
| **Recuperabilidad** | Reinicio de `replica1` tras acumular cambios en `primary` | *Streaming WAL* (`wal_keep_size=256MB`) + `2/2` sondeos `pg_is_in_recovery() == true` | Resincronización automática y retorno al Round-Robin (`P08`) |
| **Observabilidad / Auditabilidad** | Necesidad de demostrar qué nodo atendió cada petición | `ApiResponse.auditoriaTecnica` con `inet_server_addr()`, `pg_is_in_recovery()` y headers `X-*` | Evidencia verificable en cada respuesta (`RF-09`, `RF-12`, `RNF-11`) |
| **Portabilidad y Seguridad** | Despliegue en máquina limpia sin secretos en Git | `Dockerfile` multi-etapa + `docker-compose.yml` + `.env` / `.env.example` | Arranque reproducible con `docker compose up -d --build` (`RNF-09`, `RNF-10`) |

---

## 2. Riesgos Técnicos y Mitigaciones

| Riesgo | Probabilidad / Impacto | Mitigación Implementada en la Arquitectura |
|---|---|---|
| **Lectura de saldo obsoleto por *replication lag* WAL** | Media / Crítico (*Fintech*) | Lecturas críticas forzadas a `PRIMARY` (`RYOW`) y soporte explícito de `X-Consistencia: CRITICA`. |
| **Ventana de errores `503`/`500` al caer abruptamente `ms-cuentas-2`** | Media / Medio | Parámetros agresivos de convergencia en Eureka (`lease-renewal=5s`, `lease-expiration=12s`, refresco caché `3–5s`) y reintento controlado en pruebas (`P03`). |
| **Hibernate abre conexión en `PRIMARY` antes del AOP** | Alta si no se controla / Crítico | `spring.jpa.open-in-view=false` + `@Order(Ordered.HIGHEST_PRECEDENCE)` en `DbRoutingAspect` antes de `@Transactional`. |
| **Condición de carrera al inicializar/migrar datos entre `ms-cuentas-1` y `ms-cuentas-2`** | Alta / Alto | Versionamiento con **Flyway** (`@FlywayDataSource` en `PRIMARY`) que usa *advisory lock* nativo de PostgreSQL (`ADR-008`). |
| **Interbloqueo (*deadlock*) en transferencias simultáneas opuestas (`A->B` y `B->A`)** | Media / Alto | Bloqueo pesimista adquirido siempre en orden lexicográfico ascendente de `numero_celular`. |
| **Caída simultánea de `replica1` y `replica2`** | Baja / Medio | Si no hay réplicas saludables, `ReplicaHealthTracker` + `DbRoutingAspect` ejecutan *fallback* controlado sobre `PRIMARY` evitando caída total de lecturas. |
| **Retraso de réplica superior a `wal_keep_size`** | Baja en laboratorio / Alto | `wal_keep_size=256MB` cubre holgadamente interrupciones temporales de `P08`; si una réplica pierde su volumen, `start-replica.sh` ejecuta `pg_basebackup` limpio. |

---

## 3. Trazabilidad Arquitectura ↔ SRS ↔ Escenarios `P01–P08`

| Componente / Mecanismo del SAD | Documentación C4 / ADR | Requisitos SRS Cubiertos | Escenarios de Verificación |
|---|---|---|---|
| `eureka-server` + clientes Eureka | [Nivel 2](02-contenedores-c4-nivel2.md), `ADR-003` | `RF-10`, `RNF-02` | `P01`, `P03` |
| `api-gateway` (`lb://` + `SetPath` + filtro traza) | [Nivel 3](03-componentes-c4-nivel3.md), `ADR-003` | `RF-11`, `RNF-01`, `RNF-02` | `P01`, `P02`, `P03` |
| `ms-cuentas` (×2 instancias + bloqueo determinístico) | [Nivel 3](03-componentes-c4-nivel3.md), [Dinámica](04-vistas-dinamicas-y-estados.md), `ADR-006` | `RF-01`–`RF-05`, `RNF-01` | `P01`–`P07` |
| `ms-transacciones` (`@LoadBalanced RestClient` + ledger) | [Nivel 3](03-componentes-c4-nivel3.md), [Dinámica](04-vistas-dinamicas-y-estados.md), `ADR-006` | `RF-06`–`RF-08`, `RF-12` | `P01`, `P04`–`P08` |
| `common-persistence` (`AbstractRoutingDataSource` + AOP) | [Nivel 3/4](03-componentes-c4-nivel3.md), [Dinámica](04-vistas-dinamicas-y-estados.md), `ADR-001`, `ADR-002` | `RF-01`–`RF-03`, `RF-07`–`RF-09`, `RF-12`, `RNF-05`–`RNF-07`, `RNF-11` | `P05`, `P06`, `P07`, `P08` |
| `ReplicaHealthTracker` (máquina de estados `2/2`) | [Estados](04-vistas-dinamicas-y-estados.md), `ADR-005` | `RF-09`, `RNF-03`, `RNF-04` | `P06`, `P08` |
| Clúster PostgreSQL 17 + `docker-compose.yml` + `.env` | [Despliegue](05-despliegue-e-infraestructura.md), `ADR-004` | `RNF-08`, `RNF-09`, `RNF-10`, `RNF-12` | `P01`–`P08` y revisión de repo |
