# 1.2 Glosario, Acrónimos y Actores

## 1. Glosario de Términos y Acrónimos

| Término / Acrónimo | Definición en el Contexto del Sistema |
|---|---|
| **CQRS Ligero** | Patrón *Command Query Responsibility Segregation* aplicado a nivel de acceso a datos: los comandos de escritura van al nodo Primario y las consultas ordinarias se distribuyen entre Réplicas de solo lectura. |
| **Read-Your-Own-Writes (RYOW)** | Garantía de consistencia de sesión/operación donde toda lectura crítica inmediata posterior a una escritura observa el estado ya confirmado en el Primario. |
| **WAL (*Write-Ahead Log*)** | Registro secuencial de transacciones de PostgreSQL transmitido por *streaming* desde `postgres-primary` hacia `postgres-replica-1` y `postgres-replica-2`. |
| **Hot Standby** | Modo de operación de una réplica PostgreSQL que permite ejecutar consultas `SELECT` de solo lectura mientras aplica continuamente los registros WAL recibidos del Primario. |
| **Replication Lag** | Diferencia temporal o de posición LSN (*Log Sequence Number*) entre la escritura confirmada en el Primario (`sent_lsn`) y su reproducción visible en una réplica (`replay_lsn`). |
| **`pg_is_in_recovery()`** | Función interna de PostgreSQL que devuelve `false` en el nodo Primario y `true` en una réplica en modo *standby*. |
| **`inet_server_addr()`** | Función SQL de PostgreSQL que devuelve la dirección IP real del servidor que atiende la conexión actual, usada en `auditoriaTecnica` como evidencia verificable. |
| **Eureka Server** | Servidor de registro y descubrimiento dinámico de microservicios mediante *heartbeats* HTTP. No administra nodos PostgreSQL. |
| **Spring Cloud LoadBalancer** | Balanceador de carga del lado del cliente que resuelve rutas lógicas `lb://<nombre-servicio>` sobre instancias saludables obtenidas desde Eureka. |
| **`AbstractRoutingDataSource`** | Clase base de Spring JDBC que delega la selección dinámica del `DataSource` físico según una clave contextual por hilo (`DbContextHolder`). |
| **P2P (*Peer-to-Peer*)** | Transferencia directa de fondos entre dos billeteras digitales identificadas por su número de celular. |
| **SRS** | *Software Requirements Specification* (Especificación de Requisitos de Software). |

---

## 2. Actores del Sistema

| Actor | Tipo | Descripción e Interacción |
|---|---|---|
| **Cliente / Usuario de Billetera** | Humano (vía App/`curl`) | Consulta su perfil, saldo y contactos; ejecuta transferencias P2P; verifica inmediatamente su nuevo saldo y comprobante. |
| **Operador / Evaluador de Infraestructura** | Humano / Script experimental | Inspecciona el tablero de Eureka, ejecuta ráfagas de carga (100+ req), provoca fallos controlados (`stop`/`kill` de instancias y réplicas) y verifica recuperación. |
| **API Gateway (`api-gateway`)** | Componente de borde | Recibe toda petición externa en el puerto `:8080` y la enruta dinámicamente mediante `lb://`. |
| **Microservicio Transacciones (`ms-transacciones`)** | Actor interno de negocio | Consume internamente a `ms-cuentas` vía `http://ms-cuentas/api/cuentas/movimiento-interno` para ejecutar débito/crédito antes de registrar la transacción. |
| **Monitor de Salud de Réplicas** | Proceso interno (`@Scheduled`) | Sondea cada 3 segundos la disponibilidad y estado `pg_is_in_recovery()` de `REPLICA_1` y `REPLICA_2`. |
