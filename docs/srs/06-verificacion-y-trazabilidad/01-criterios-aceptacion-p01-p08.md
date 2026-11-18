# 6.1 Criterios de Aceptación y Protocolo Experimental (P01–P08)

Cada escenario experimental obligatorio de la actividad queda especificado con precondiciones, procedimiento de prueba, evidencia verificable y criterio de aceptación.

---

## `P01` · Descubrimiento Dinámico
- **Requisitos verificados:** `RF-10`, `RF-11`
- **Precondiciones:** Los 8 contenedores levantados y sanos (`docker compose ps`).
- **Procedimiento:**
  1. Consultar `GET http://localhost:8761/eureka/apps` (`Accept: application/json`).
  2. Enviar solicitudes funcionales vía Gateway (`GET http://localhost:8080/api/cuentas/0991112233` y `GET http://localhost:8080/api/transacciones/historial/0991112233`).
- **Criterios de aceptación:**
  - `MS-CUENTAS` aparece registrado con `2` instancias `UP` (`8081` y `8082`).
  - `MS-TRANSACCIONES` aparece registrado con `1` instancia `UP` (`8083`).
  - Las solicitudes vía Gateway (`:8080`) responden `200 OK` sin rutas fijas.

---

## `P02` · Balanceo HTTP
- **Requisitos verificados:** `RF-11`, `RNF-01`
- **Precondiciones:** Ambas instancias `ms-cuentas-1` y `ms-cuentas-2` registradas en `UP` en Eureka.
- **Procedimiento:**
  1. Ejecutar un script con `100` o más solicitudes consecutivas `GET http://localhost:8080/api/cuentas/0991112233` (o `/api/cuentas/instancia`).
  2. Contabilizar el valor del encabezado `X-Service-Instance` / `auditoriaTecnica.servicioOrigen` por cada respuesta.
- **Criterios de aceptación:**
  - `100/100` respuestas exitosas (`HTTP 200`).
  - Distribución equilibrada entre `ms-cuentas-1` y `ms-cuentas-2` (aprox. `50 / 50`, nunca `100 / 0`).

---

## `P03` · Fallo de Instancia
- **Requisitos verificados:** `RF-10`, `RNF-02`
- **Precondiciones:** Tráfico periódico activo contra `GET http://localhost:8080/api/cuentas/0991112233`.
- **Procedimiento:**
  1. Registrar respuestas normales (ambas instancias respondiendo).
  2. Ejecutar `docker compose stop ms-cuentas-2` durante la ráfaga.
  3. Medir posibles errores transitorios, tiempo de detección en Gateway/Eureka y continuidad exclusiva sobre `ms-cuentas-1`.
  4. Ejecutar `docker compose start ms-cuentas-2` y medir tiempo hasta que vuelve a recibir tráfico balanceado.
- **Criterios de aceptación:**
  - El sistema continúa atendiendo peticiones mediante `ms-cuentas-1` tras la ventana de detección.
  - Al reiniciar `ms-cuentas-2`, vuelve a registrarse en Eureka y reanuda participación en el balanceo.

---

## `P04` · Comunicación entre Servicios
- **Requisitos verificados:** `RF-04`, `RF-06`, `RF-12`
- **Precondiciones:** Cuenta origen (`0991112233`) y destino (`0984445566`) activas en `cuentas_db`.
- **Procedimiento:**
  1. Caso exitoso: `POST http://localhost:8080/api/transacciones/transferir` con monto válido (`$25.00`).
  2. Caso de error controlado: repetir con monto mayor al saldo disponible o límite diario.
- **Criterios de aceptación:**
  - Caso exitoso retorna `201 Created`, descuenta origen, acredita destino, persiste en `tx_db.transacciones` y evidencia `instanciaCuentasConsultada` en `auditoriaTecnica`.
  - Caso de error retorna `400`/`409` controlado sin alterar saldos.

---

## `P05` · Enrutamiento de Base de Datos
- **Requisitos verificados:** `RF-01`, `RF-02`, `RF-07`, `RNF-05`, `RNF-07`
- **Precondiciones:** `primary`, `replica1` y `replica2` en estado sano; `pg_stat_replication` mostrando 2 réplicas en `streaming`.
- **Procedimiento:**
  1. Ejecutar una transferencia (`POST /api/transacciones/transferir`).
  2. Ejecutar `20` consultas ordinarias (`GET /api/cuentas/0991112233/contactos` y `GET /api/transacciones/historial/0991112233`).
  3. Consultar `GET http://localhost:8080/api/cuentas/db/estado` y logs de aplicación.
- **Criterios de aceptación:**
  - La escritura muestra `nodoBaseDatos` apuntando a `primary` (`recovery=false`).
  - Las lecturas ordinarias muestran `recovery=true` y reparto equilibrado entre `REPLICA_1` y `REPLICA_2` con sus respectivas IPs (`inet_server_addr()`).

---

## `P06` · Fallo de Réplica PostgreSQL
- **Requisitos verificados:** `RNF-03`
- **Precondiciones:** Ambas réplicas sanas y atendiendo lecturas.
- **Procedimiento:**
  1. Ejecutar `docker compose stop replica1`.
  2. Lanzar inmediatamente una serie de consultas `GET /api/cuentas/0991112233/contactos` y `GET /api/transacciones/historial/0991112233`.
  3. Consultar `GET http://localhost:8080/api/cuentas/db/estado` y logs de `ReplicaHealthTracker`.
- **Criterios de aceptación:**
  - Las consultas continúan respondiendo `HTTP 200 OK` usando `REPLICA_2` (`0` fallos al cliente).
  - `/api/cuentas/db/estado` muestra `REPLICA_1` con `available=false` y `REPLICA_2` con `available=true`.

---

## `P07` · Consistencia de Lectura
- **Requisitos verificados:** `RF-03`, `RF-08`, `RNF-06`
- **Precondiciones:** Cuenta origen con saldo conocido.
- **Procedimiento:**
  1. Ejecutar `POST /api/transacciones/transferir` descontando `$25.00`.
  2. De forma inmediata (siguiente petición secuencial), consultar `GET /api/cuentas/{origen}/saldo-critico` y `GET /api/transacciones/comprobante/{codigo}`.
  3. Opcionalmente probar `GET /api/cuentas/{origen}` con header `X-Consistencia: CRITICA`.
- **Criterios de aceptación:**
  - Las lecturas críticas muestran el saldo descontado y el comprobante recién creado sin esperar propagación asíncrona.
  - `auditoriaTecnica` confirma `recovery=false` (`PRIMARY`) y `politicaEnrutamiento = LECTURA_CRITICA_PRIMARIO`.

---

## `P08` · Recuperación de Réplica
- **Requisitos verificados:** `RNF-04`, `RNF-08`
- **Precondiciones:** `replica1` detenida tras P06, con escrituras nuevas generadas mientras estuvo caída.
- **Procedimiento:**
  1. Ejecutar `docker compose start replica1`.
  2. Verificar en el Primario `SELECT application_name, state, sent_lsn, replay_lsn FROM pg_stat_replication;`.
  3. Consultar `GET http://localhost:8080/api/cuentas/db/estado` hasta observar 2 sondeos exitosos y `available=true`.
  4. Ejecutar nuevas consultas ordinarias y verificar que `REPLICA_1` vuelve a incrementar su contador `queriesServed`.
- **Criterios de aceptación:**
  - `replica1` sincroniza WAL pendientes (`state = streaming`), supera los 2 chequeos `pg_is_in_recovery() = true` y vuelve a participar en el *Round-Robin*.
