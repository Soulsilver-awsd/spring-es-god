# Evidencia de ejecución P01–P08

Salida real de [`curl-p01-p08.sh`](curl-p01-p08.sh) contra el entorno completo levantado desde cero. Criterios: [01-criterios-aceptacion-p01-p08.md](../srs/06-verificacion-y-trazabilidad/01-criterios-aceptacion-p01-p08.md).

## Entorno

- Fecha: 2026-11-19. Host Fedora Linux 44 (x86_64, 8 CPU, 15 GB RAM) con Podman 5.8.7 y Docker Compose 5.6.0.
- Despliegue limpio: `docker compose down -v && docker compose up -d --build`, con un `.env` local que define las mismas claves que `.env.example` y contraseñas propias.
- Validación de la plantilla: tras otro `down -v`, `docker compose --env-file .env.example up -d --build` dejó los 8 contenedores en `healthy`, y `P01`, `P02`, `P04` y `P07` pasaron (17 OK, 0 FALLAS) con las credenciales `CAMBIAR_*` de ejemplo.
  - Primera construcción de las 4 imágenes (sin caché de Maven): ~4 min 40 s.
  - Con las imágenes ya construidas, `up -d --build` termina en ~55 s, cuando `api-gateway` arranca tras los `healthcheck` de sus dependencias.
- Estado de los contenedores antes de las pruebas (`docker inspect --format '{{.State.Health.Status}}'`): los 8 en `healthy`.
- Flyway con arranque simultáneo de `ms-cuentas-1` y `ms-cuentas-2`: una instancia aplicó `V1` y `V2` y la otra registró `Schema "cuentas_db" is up to date. No migration necessary.`

## Resultado

**31 OK, 0 FALLAS** (código de salida `0`).

| Prueba | Resultado clave |
|---|---|
| `P01` | `MS-CUENTAS` 2 `UP` (`ms-cuentas-1:8081`, `ms-cuentas-2:8082`), `MS-TRANSACCIONES` 1 `UP`; `200` vía `:8080` |
| `P02` | 120/120 `200`, reparto exacto 60 / 60 |
| `P03` | 171 peticiones con 0 errores; convergencia a `ms-cuentas-1` en cuanto termina el `stop`; `ms-cuentas-2` vuelve al balanceo en ~26 s (arranque de la JVM y registro) |
| `P04` | `201` (`TX-2026-0001`, `instanciaCuentasConsultada = ms-cuentas-1:8081`), 500.00 → 475.00 / 150.00 → 175.00; `9999.00` → `409 Saldo insuficiente` sin cambiar saldos |
| `P05` | Escritura en `PRIMARY recovery=false`; 20 lecturas 9 / 11 entre `REPLICA_1` y `REPLICA_2` (`recovery=true`); 2 réplicas en `streaming` |
| `P06` | 20/20 `200` tras `stop replica1` (2 con `X-Db-Fallback: true` por failover transparente); después, 100% en `REPLICA_2`; `REPLICA_1 available=false` |
| `P07` | `saldo-critico` y `comprobante` inmediatos con `LECTURA_CRITICA_PRIMARIO` en `PRIMARY recovery=false`; saldo exacto 476.00 → 451.00 |
| `P08` | `REPLICA_1 available=true` en ~5–8 s tras 2/2 sondeos; `replay_lsn` igual al primario; 9–10 de 20 lecturas vuelven a `REPLICA_1` |

## Salida completa

```text

=== P01 Descubrimiento dinamico en Eureka y acceso via Gateway ===
  API-GATEWAY: api-gateway:92683a9170f117130b7c841a83bbdf2d:8080 UP
  MS-TRANSACCIONES: ms-transacciones:7133b147e1b029da6601f3cc9a717d20:8083 UP
  MS-CUENTAS: ms-cuentas-2:8082 UP, ms-cuentas-1:8081 UP
  [OK] MS-CUENTAS con 2 instancias UP (2)
  [OK] MS-TRANSACCIONES con 1 instancia UP (1)
  [OK] GET :8080/api/cuentas/0991112233 -> 200 via ms-cuentas-1:8081 (X-Gateway-Handled: api-gateway)
  [OK] GET :8080/api/transacciones/historial/0991112233 -> 200 via ms-transacciones:8083

=== P02 Balanceo HTTP con 120 peticiones a /api/cuentas/instancia ===
       60 200 ms-cuentas-1:8081
       60 200 ms-cuentas-2:8082
  [OK] 120/120 respuestas 200 (120)
  [OK] reparto equilibrado ms-cuentas-1=60 / ms-cuentas-2=60 (minimo 40 cada una)

=== P03 Fallo de instancia: stop/start de ms-cuentas-2 con trafico continuo ===
  ms-cuentas-2 detenido en 8914 ms; esperando convergencia del Gateway...
  [OK] convergencia exclusiva a ms-cuentas-1 en 8934 ms
  errores transitorios durante la ventana de deteccion: 0 
  ms-cuentas-2 arrancado; esperando que vuelva a recibir trafico...
  [OK] ms-cuentas-2 reincorporado al balanceo en 26237 ms (arranque JVM + registro Eureka)
  [OK] Eureka vuelve a mostrar 2 instancias UP de MS-CUENTAS
  total peticiones: 171, no-200: 0

=== P04 Comunicacion entre servicios: transferencia exitosa y rechazo controlado ===
  saldos iniciales: 0991112233=500.00 0984445566=150.00
  {"codigo":"TX-2026-0001","estado":"EXITOSA","auditoria":{"servicioOrigen":"ms-transacciones:8083","instanciaCuentasConsultada":"ms-cuentas-1:8081","nodoBaseDatos":"PRIMARY (10.89.13.2:5432, recovery=false)","politicaEnrutamiento":"ESCRITURA_DIRECTA"}}
  [OK] transferencia de 25.00 -> 201
  [OK] instanciaCuentasConsultada = ms-cuentas-1:8081
  [OK] origen descontado (500.00 -> 475.00) y destino acreditado (150.00 -> 175.00)
  [OK] transferencia de 9999.00 -> 409 "Saldo insuficiente"
  [OK] el rechazo no altera el saldo de origen (475.00)

=== P05 Enrutamiento de BD: escritura en PRIMARY y 20 lecturas en replicas ===
  pg_stat_replication en primary:
    walreceiver|10.89.13.5|streaming
    walreceiver|10.89.13.6|streaming
  [OK] escritura en PRIMARY (10.89.13.2:5432, recovery=false)
        9 200 REPLICA_1 false
       11 200 REPLICA_2 false
  [OK] 20/20 lecturas 200
  [OK] reparto Round-Robin REPLICA_1=9 / REPLICA_2=11
  [OK] lectura ordinaria con recovery=true: REPLICA_1 (10.89.13.5:5432, recovery=true)
  /api/cuentas/db/estado: {"consultasTotales":{"REPLICA_1":111,"REPLICA_2":111,"PRIMARY":4},"replicas":[{"nodo":"REPLICA_1","available":true},{"nodo":"REPLICA_2","available":true}]}

=== P06 Fallo de replica: stop replica1 durante lecturas ===
  replica1 detenida
       18 200 REPLICA_2 false
        2 200 REPLICA_2 true
  [OK] 20/20 lecturas 200 (0 fallos al cliente)
  lecturas con X-Db-Fallback: true (failover transparente antes de la sonda): 2
  [OK] tras la deteccion, 100% de lecturas en REPLICA_2
  [OK] /api/cuentas/db/estado: REPLICA_1 available=false, REPLICA_2 available=true
  [OK] /api/transacciones/db/estado: REPLICA_1 available=false

=== P07 Consistencia de lectura (RYOW): transferencia + lecturas criticas inmediatas ===
  [OK] transferencia 25.00 -> 201 (TX-2026-0004)
  [OK] saldo-critico inmediato descontado (476.00 -> 451.00)
  [OK] saldo-critico: LECTURA_CRITICA_PRIMARIO en PRIMARY (10.89.13.2:5432, recovery=false)
  [OK] comprobante TX-2026-0004 visible de inmediato -> 200
  [OK] comprobante: LECTURA_CRITICA_PRIMARIO en PRIMARY (10.89.13.2:5432, recovery=false)
  [OK] X-Consistencia: CRITICA -> PRIMARY (10.89.13.2:5432, recovery=false), saldo 451.00

=== P08 Recuperacion de replica: start replica1 y retorno al Round-Robin ===
  replica1 arrancada; sondeando /api/cuentas/db/estado...
  [OK] REPLICA_1 available=true en 4836 ms (2/2 sondeos pg_is_in_recovery())
  {"nodo":"REPLICA_1","available":false,"consecutiveSuccesses":1,"lastReplayLsn":"0/505A698"}
{"nodo":"REPLICA_2","available":true,"consecutiveSuccesses":128,"lastReplayLsn":"0/505A698"}
    walreceiver|10.89.13.6|streaming|0/505A698|0/505A698
    walreceiver|10.89.13.11|streaming|0/505A698|0/505A698
  [OK] 2 replicas en streaming en pg_stat_replication (LSN primario al detener: 0/505A698)
        9 200 REPLICA_1 false
       11 200 REPLICA_2 false
  [OK] REPLICA_1 vuelve al Round-Robin (9 de 20 lecturas)

=== Resumen: 31 OK, 0 FALLAS ===
```

### Repetición de P06 y P08

Ejecución posterior de `./docs/api/curl-p01-p08.sh P06 P08`. En esta versión del script, el estado de réplica de `ms-cuentas` se consulta en sus 2 instancias, porque cada una tiene su propio `ReplicaHealthTracker`:

```text

=== P06 Fallo de replica: stop replica1 durante lecturas ===
  replica1 detenida
       18 200 REPLICA_2 false
        2 200 REPLICA_2 true
  [OK] 20/20 lecturas 200 (0 fallos al cliente)
  lecturas con X-Db-Fallback: true (failover transparente antes de la sonda): 2
  [OK] tras la deteccion, 100% de lecturas en REPLICA_2
  [OK] /api/cuentas/db/estado: REPLICA_1 available=false, REPLICA_2 available=true
  [OK] /api/transacciones/db/estado: REPLICA_1 available=false

=== P08 Recuperacion de replica: start replica1 y retorno al Round-Robin ===
  replica1 arrancada; sondeando /api/cuentas/db/estado...
  [OK] REPLICA_1 available=true en ms-cuentas-1 y ms-cuentas-2 en 8122 ms (2/2 sondeos pg_is_in_recovery())
  {"nodo":"REPLICA_1","available":true,"consecutiveSuccesses":2,"lastReplayLsn":"0/505AA18"}
{"nodo":"REPLICA_2","available":true,"consecutiveSuccesses":22,"lastReplayLsn":"0/505AA18"}
    walreceiver|10.89.13.6|streaming|0/505AA18|0/505AA18
    walreceiver|10.89.13.12|streaming|0/505AA18|0/505AA18
  [OK] 2 replicas en streaming en pg_stat_replication (LSN primario al detener: 0/505A9E0)
       10 200 REPLICA_1 false
       10 200 REPLICA_2 false
  [OK] REPLICA_1 vuelve al Round-Robin (10 de 20 lecturas)

=== Resumen: 7 OK, 0 FALLAS ===
```

## Notas

- **`P03`:** antes de este cambio, el Gateway seguía enviando tráfico a `ms-cuentas-2` durante ~33 s, con 12 errores de 171 peticiones (`500` por *connection refused* y timeouts de `curl`). Ahora:
  - `eureka-server` publica las bajas sin la caché de solo lectura de 30 s (`use-read-only-response-cache: false`).
  - `api-gateway` reintenta los `GET` solo ante errores de conexión, sobre otra instancia, con un `connect-timeout` de 2 s. Los `POST` nunca se reintentan.
- **`P06`:** el número de lecturas con `X-Db-Fallback: true` depende de cuántas peticiones lleguen a `REPLICA_1` antes de que la sonda de 3 s la marque como no disponible.
- **PowerShell:** [`curl-p01-p08.ps1`](curl-p01-p08.ps1) implementa los mismos pasos y aserciones; esta evidencia se generó con la versión Bash.
