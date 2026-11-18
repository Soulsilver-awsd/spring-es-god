# 6. Registro de Decisiones Arquitectónicas (ADRs)

**Documentos relacionados:** [Índice del SAD](README.md) · [Requisitos No Funcionales](../srs/04-requisitos-no-funcionales/01-rnf-disponibilidad-fallos.md) · [Restricciones](../srs/02-descripcion-general/03-supuestos-dependencias.md)

---

## Índice de Decisiones

| ID | Título | Estado | Requisitos Relacionados |
|---|---|---|---|
| `ADR-001` | Enrutamiento JDBC con `AbstractRoutingDataSource` + AOP `@Order(HIGHEST_PRECEDENCE)` | Aceptada | `RNF-05`, `RNF-07` |
| `ADR-002` | Consistencia fuerte *Read-Your-Own-Writes* selectiva en `PRIMARY` | Aceptada | `RF-03`, `RF-08`, `RNF-06` |
| `ADR-003` | Separación estricta entre Eureka (HTTP) y `common-persistence` (JDBC) | Aceptada | `RF-10`, `RF-11`, `RNF-01`, `RNF-02` |
| `ADR-004` | Aislamiento lógico por esquemas y roles sobre clúster PostgreSQL único | Aceptada | `RNF-08`, `RNF-10` |
| `ADR-005` | Reincorporación de réplicas condicionada a `pg_is_in_recovery()` (`2/2` sondeos) | Aceptada | `RNF-03`, `RNF-04` |
| `ADR-006` | Orquestación P2P síncrona con bloqueo determinístico en lugar de Sagas/2PC | Aceptada | `RF-04`, `RF-06` |
| `ADR-007` | Verificación HTTP mediante `curl` y scripts CLI reproducibles (sin Postman) | Aceptada | `RNF-10`, `RNF-12` |
| `ADR-008` | Versionamiento de esquemas de BD con Flyway (`@FlywayDataSource` en `PRIMARY`) | Aceptada | `RNF-08`, `RNF-10` |

---

## `ADR-001` · Enrutamiento JDBC con `AbstractRoutingDataSource` + AOP Pre-Transaccional

- **Contexto:** Se requiere separar físicamente escrituras y lecturas críticas hacia `PRIMARY`, y lecturas ordinarias en *Round-Robin* entre `REPLICA_1` y `REPLICA_2`, garantizando trazabilidad real del nodo PostgreSQL que atendió la consulta.
- **Decisión:** Implementar `CustomRoutingDataSource` extendiendo `AbstractRoutingDataSource` con 3 `HikariDataSource` independientes, gobernado por `DbRoutingAspect` (`@Order(Ordered.HIGHEST_PRECEDENCE)`) y `spring.jpa.open-in-view=false`.
- **Alternativas descartadas:**
  1. `@Transactional(readOnly = true)` únicamente: insuficientes garantías de balanceo Round-Robin y *failover* activo entre 2 réplicas, además de depender de configuraciones específicas de driver.
  2. Proxy SQL externo (Pgpool-II / HAProxy): oculta la lógica de enrutamiento fuera de la aplicación Spring y dificulta la auditoría granular por endpoint/cabecera (`X-Consistencia`) y el reporte en `/api/*/db/estado`.
- **Consecuencias:** Control programático total en Java, métricas por nodo y pruebas `P05–P08` deterministas. Exige disciplina estricta para no romper el orden AOP y mantener `open-in-view=false`.

---

## `ADR-002` · Consistencia Fuerte *Read-Your-Own-Writes* (RYOW) Selectiva

- **Contexto:** La replicación WAL de PostgreSQL configurada es asíncrona (`sync_state = async`). Si un usuario transfiere `$25.00` y de inmediato consulta su saldo en una réplica con *replication lag*, podría ver su saldo anterior (*double-spending* percibido).
- **Decisión:** Enrutar a `PRIMARY` las lecturas críticas (`GET /api/cuentas/{celular}/saldo-critico`, `GET /api/transacciones/comprobante/{codigo}`) y cualquier lectura ordinaria que incluya el encabezado `X-Consistencia: CRITICA`, dejando el resto de lecturas ordinarias en réplicas.
- **Alternativas descartadas:**
  1. Replicación síncrona global (`synchronous_commit = remote_apply`): penaliza la latencia de escritura y degrada disponibilidad si una réplica cae.
  2. Enviar todas las lecturas a `PRIMARY`: anula el propósito de descargar lecturas hacia las réplicas.
- **Consecuencias:** Protege la integridad percibida del saldo financiero sin sacrificar la escalabilidad de consultas ordinarias (historial, contactos, perfil general).

---

## `ADR-003` · Separación de Descubrimiento HTTP (Eureka) y Enrutamiento JDBC

- **Contexto:** El sistema combina balanceo horizontal de microservicios (`ms-cuentas-1`, `ms-cuentas-2`) con balanceo de réplicas PostgreSQL (`replica1`, `replica2`).
- **Decisión:** Utilizar `eureka-server` + `Spring Cloud LoadBalancer` exclusivamente para servicios HTTP (`lb://ms-cuentas`, `lb://ms-transacciones`), y delegar el enrutamiento JDBC exclusivamente a `common-persistence`.
- **Alternativas descartadas:** Registrar instancias de PostgreSQL en Eureka o usar rutas HTTP estáticas (`localhost:8081`) entre `api-gateway`, `ms-transacciones` y `ms-cuentas`.
- **Consecuencias:** Arquitectura limpia alineada con las responsabilidades nativas de Spring Cloud; ante caída de `ms-cuentas-2` (`P03`), Eureka converge automáticamente sin mezclar estados SQL.

---

## `ADR-004` · Aislamiento Lógico por Esquemas (`cuentas_db`, `tx_db`) sobre Clúster Único

- **Contexto:** El principio *Database-per-Service* prohíbe compartir tablas entre `ms-cuentas` y `ms-transacciones`, mientras que el entorno Docker debe mantenerse liviano y reproducible (`8` contenedores en total).
- **Decisión:** Desplegar un único clúster PostgreSQL 17 replicado (1 Primario + 2 Réplicas) con la base `laboratorio`, particionado en dos esquemas independientes (`cuentas_db` y `tx_db`) y dos usuarios con permisos disjuntos (`cuentas_user` y `tx_user`), sin claves foráneas inter-esquema.
- **Alternativas descartadas:** Levantar 2 clústeres PostgreSQL completos (6 contenedores solo de BD), lo cual duplicaría consumo de RAM/CPU y complejidad de inicialización sin aportar aislamiento funcional adicional frente a roles/esquemas disjuntos.
- **Consecuencias:** Mantiene estricto desacoplamiento de datos y portabilidad Docker; ambos servicios comparten los mismos límites de capacidad física del nodo `primary`.

---

## `ADR-005` · Reincorporación de Réplicas Basada en `pg_is_in_recovery()` (`2/2` Sondeos)

- **Contexto:** Tras ejecutar `docker compose start replica1` (`P08`), el contenedor puede abrir el puerto TCP `5432` antes de que PostgreSQL termine el arranque en *hot standby* y aplique WAL pendiente.
- **Decisión:** El monitor `@Scheduled(fixedDelay = 3000)` en `ReplicaHealthTracker` valida SQL real (`SELECT pg_is_in_recovery(), COALESCE(pg_last_wal_replay_lsn()::text, 'none')`) y requiere `2` sondeos consecutivos exitosos con `recovery = true` antes de reincorporar la réplica al Round-Robin.
- **Alternativas descartadas:** Chequeo TCP simple o reincorporación inmediata al primer ping exitoso.
- **Consecuencias:** Previene errores intermitentes al reiniciar réplicas y evita dirigir consultas a un nodo que no esté operando como *standby* válido.

---

## `ADR-006` · Orquestación Síncrona P2P con Bloqueo Determinístico

- **Contexto:** Una transferencia P2P involucra debitar/acreditar dos cuentas en `ms-cuentas` y registrar el comprobante en `ms-transacciones`.
- **Decisión:** `ms-transacciones` invoca de forma síncrona vía `@LoadBalanced RestClient` a `POST http://ms-cuentas/api/cuentas/movimiento-interno`, donde `ms-cuentas` ejecuta débito y crédito en una única transacción ACID con bloqueo pesimista ordenado determinísticamente, y luego `ms-transacciones` persiste el comprobante en `tx_db`.
- **Alternativas descartadas:** Transacciones distribuidas 2PC/XA o coreografía asíncrona con Kafka/RabbitMQ (explícitamente fuera de alcance en el SRS).
- **Consecuencias:** Baja complejidad operativa y respuesta inmediata al usuario (`201 Created` o rechazo `400`/`409` sin alterar saldos). Si fallara la escritura posterior en `tx_db` tras el `200 OK` de `ms-cuentas`, se documenta como riesgo residual acotado fuera del alcance de Sagas.

---

## `ADR-007` · Verificación HTTP mediante `curl` y Scripts CLI Reproducibles (sin Postman)

- **Contexto:** Los escenarios experimentales `P01–P08` exigen ráfagas de `100+` peticiones HTTP, inspección exacta de cabeceras de trazabilidad (`X-Service-Instance`, `X-Db-Node`, `X-Db-Fallback`, `X-Gateway-Handled`), pruebas automatizadas repetibles y portabilidad total (`RNF-10`, `RNF-12`).
- **Decisión:** Estandarizar todas las pruebas y documentación de consumo HTTP usando **`curl` directamente** desde terminal junto con scripts reproducibles (`.sh` y `.ps1`) y contrato formal OpenAPI 3.0.3 en [docs/api/](../api/README.md), prescindiendo de Postman.
- **Alternativas descartadas:** Colecciones propietarias de Postman o clientes GUI dependientes de instalación manual por usuario.
- **Consecuencias:** Cualquier integrante o evaluador puede ejecutar `P01–P08` de forma determinista desde Bash o PowerShell sin software adicional ni cuentas externas, facilitando además el conteo automático de distribución entre instancias y réplicas.

---

## `ADR-008` · Versionamiento de Esquemas de Base de Datos con Flyway (`@FlywayDataSource` en `PRIMARY`)

- **Contexto:** Con `spring.jpa.hibernate.ddl-auto=validate`, el sistema necesita evolucionar y versionar de forma controlada las tablas, índices y datos semilla de `cuentas_db` y `tx_db` sin sufrir condiciones de carrera entre `ms-cuentas-1` y `ms-cuentas-2` ni intentar escribir sobre réplicas *Hot Standby*.
- **Decisión:** Adoptar **Flyway** (`flyway-core` + `flyway-database-postgresql`) con historiales aislados por esquema (`cuentas_db.flyway_schema_history` y `tx_db.flyway_schema_history`) y un bean dedicado `@FlywayDataSource` en `common-persistence` apuntando directamente a `dsPrimary` (`PRIMARY`).
- **Alternativas descartadas:**
  1. `hibernate.ddl-auto=update`: no es determinista, no versiona cambios incrementales ni datos semilla, y produce condiciones de carrera en arranque paralelo.
  2. Scripts SQL manuales o inicializadores Java *ad-hoc*: carecen de historial versionado con validación de *checksum* (`validate-on-migrate`).
  3. Liquibase: mayor verbosidad XML/YAML para un proyecto donde SQL nativo de PostgreSQL 17 es más directo y legible.
- **Consecuencias:** Trazabilidad completa de cambios DDL/datos por versión (`V1__`, `V2__`), sincronización segura entre `ms-cuentas-1` y `ms-cuentas-2` mediante el *advisory lock* nativo de Flyway y propagación automática vía WAL hacia `replica1` y `replica2`. Exige tratar las migraciones ya aplicadas como inmutables.
