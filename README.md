**Este proyecto es producto de una actividad en clases**

El link al video de presentación se encuentra en:

> https://drive.google.com/file/d/10-gmY0eYT0AMnLySES2HSBplX-U6U11E/view?usp=sharing

# Billetera Digital Distribuida

Billetera P2P con microservicios Spring Boot 3.4.3 (Java 21), descubrimiento con Eureka, API Gateway con balanceo `lb://` y un clúster PostgreSQL 17 (1 primario + 2 réplicas *hot standby* por streaming WAL) con enrutamiento lectura/escritura (CQRS-lite).

| Contenedor | Puerto host | Rol |
|---|---|---|
| `api-gateway` | `8080` | Punto único de entrada (`/api/cuentas/**`, `/api/transacciones/**`) |
| `eureka-server` | `8761` | Registro y descubrimiento de servicios |
| `ms-cuentas-1` / `ms-cuentas-2` | `8081` / `8082` | Cuentas, saldos y movimientos atómicos (`cuentas_db`) |
| `ms-transacciones` | `8083` | Orquestación de transferencias y comprobantes (`tx_db`) |
| `primary` | `5432` | PostgreSQL primario (escrituras y lecturas críticas) |
| `replica1` / `replica2` | `5433` / `5434` | Réplicas de lectura (*Round-Robin* con failover) |

Documentación: [SRS](docs/srs/README.md) · [SAD (C4 + ADRs)](docs/sad/README.md) · [SDD](docs/sdd/README.md) · [API REST y `curl`](docs/api/README.md) · [OpenAPI](docs/api/openapi.yaml)

## Requisitos

- Docker con Docker Compose v2 (o Podman con `docker compose`). Unos 4 GB de RAM libres: cada servicio Java tiene un límite de `640m`.
- Para los scripts de verificación: `curl`, `jq` y `bc` (Linux/macOS/WSL) o PowerShell 5.1+ con `curl.exe` (Windows).
- No hace falta Java ni Maven en el host: los `Dockerfile` multi-etapa compilan dentro de `maven:3.9-eclipse-temurin-21-alpine`.

## Despliegue

Desde la raíz del repositorio, en una máquina limpia:

```bash
cp .env.example .env          # opcional: cambiar las contraseñas CAMBIAR_* (nunca versionar .env)
docker compose up -d --build  # construye las 4 imágenes y levanta los 8 contenedores
docker compose ps             # esperar a que los 8 servicios estén "healthy"
```

Orden de arranque garantizado por `depends_on` + `healthcheck`:

1. `primary` sano → `replica1` y `replica2` (copia base con `pg_basebackup`).
2. `eureka-server` sano.
3. `ms-cuentas-1`, `ms-cuentas-2` y `ms-transacciones` (requieren `primary` y `eureka-server` sanos). Las dos instancias de `ms-cuentas` arrancan en paralelo; Flyway serializa las migraciones con un *advisory lock* de PostgreSQL.
4. `api-gateway` (requiere `eureka-server` sano).

Comprobación rápida:

```bash
curl -s http://localhost:8080/api/cuentas/0991112233 | jq
curl -s -H 'Accept: application/json' http://localhost:8761/eureka/apps | jq '.applications.application[].name'
```

Reiniciar desde cero (borra los volúmenes y vuelve a aplicar las migraciones y los datos semilla):

```bash
docker compose down -v && docker compose up -d --build
```

## Pruebas P01–P08

El enunciado de los 8 escenarios obligatorios y las evidencias que exige cada uno están en [pruebas obligatorias P01–P08](docs/srs/06-verificacion-y-trazabilidad/03-pruebas-obligatorias-p01-p08.md). Los [criterios de aceptación P01–P08](docs/srs/06-verificacion-y-trazabilidad/01-criterios-aceptacion-p01-p08.md) los detallan con precondiciones, procedimiento y criterio verificable. Se pueden ejecutar de dos formas: con el script automatizado o paso a paso.

### Ejecución automatizada

Los scripts usan solo `curl` y `docker compose`, comprueban cada criterio y terminan con un resumen (código de salida `0` si todo pasa):

```bash
./docs/api/curl-p01-p08.sh            # Linux / macOS / WSL
./docs/api/curl-p01-p08.sh P03 P06    # solo algunas pruebas
```

```powershell
.\docs\api\curl-p01-p08.ps1           # Windows PowerShell
.\docs\api\curl-p01-p08.ps1 P03 P06
```

`P03`, `P06` y `P08` detienen y arrancan contenedores, y los dejan en su estado inicial. `P04`, `P05`, `P07` y `P08` hacen transferencias reales: tras unas 6 ejecuciones completas se agota el límite diario de `0991112233` (`300.00`) y hay que reiniciar con `docker compose down -v && docker compose up -d --build`.

La salida de una ejecución completa (31 OK, 0 FALLAS) está en [docs/api/evidencia-p01-p08.md](docs/api/evidencia-p01-p08.md).

### Resumen

| Prueba | Escenario | Requisitos | Criterio de aceptación |
|---|---|---|---|
| `P01` | Descubrimiento dinámico | `RF-10`, `RF-11` | `MS-CUENTAS` con 2 instancias `UP` (`8081`, `8082`), `MS-TRANSACCIONES` con 1 (`8083`); `200` vía `:8080` sin rutas fijas |
| `P02` | Balanceo HTTP | `RF-11`, `RNF-01` | 100/100 `200`; reparto aprox. 50/50 entre `ms-cuentas-1` y `ms-cuentas-2`, nunca 100/0 |
| `P03` | Fallo de instancia | `RF-10`, `RNF-02` | Tras la ventana de detección atiende solo `ms-cuentas-1`; al reiniciar, `ms-cuentas-2` vuelve a Eureka y al balanceo |
| `P04` | Comunicación entre servicios | `RF-04`, `RF-06`, `RF-12` | `201` con `instanciaCuentasConsultada`, origen descontado y destino acreditado; error `400`/`409` sin alterar saldos |
| `P05` | Enrutamiento de base de datos | `RF-01`, `RF-02`, `RF-07`, `RNF-05`, `RNF-07` | Escritura en `PRIMARY` (`recovery=false`); lecturas con `recovery=true` repartidas entre `REPLICA_1` y `REPLICA_2` |
| `P06` | Fallo de réplica PostgreSQL | `RNF-03` | 0 fallos al cliente usando `REPLICA_2`; `REPLICA_1 available=false`, `REPLICA_2 available=true` |
| `P07` | Consistencia de lectura | `RF-03`, `RF-08`, `RNF-06` | Saldo descontado y comprobante visibles de inmediato, con `recovery=false` y `LECTURA_CRITICA_PRIMARIO` |
| `P08` | Recuperación de réplica | `RNF-04`, `RNF-08` | `replica1` en `streaming`, 2/2 sondeos `pg_is_in_recovery() = true` y vuelta al *Round-Robin* |

### Procedimiento manual

Todas las peticiones pasan por el Gateway (`:8080`). Las respuestas incluyen las cabeceras `X-Service-Instance` (instancia que atendió), `X-Db-Node` (nodo PostgreSQL usado) y `X-Db-Fallback` (failover de réplica), además del bloque `auditoriaTecnica` del cuerpo. Las consultas `psql` usan las variables `POSTGRES_USER` y `POSTGRES_DB` del propio contenedor, así que no hace falta escribir credenciales.

Cuentas semilla usadas: origen `0991112233` y destino `0984445566`.

#### `P01` · Descubrimiento dinámico

**Precondiciones:** los 8 contenedores levantados y `healthy`.

```bash
docker compose ps
curl -s -H 'Accept: application/json' http://localhost:8761/eureka/apps \
  | jq -r '.applications.application[] | "\(.name): \([.instance[] | "\(.instanceId) \(.status)"] | join(", "))"'
curl -i http://localhost:8080/api/cuentas/0991112233
curl -i http://localhost:8080/api/transacciones/historial/0991112233
```

**Criterios de aceptación:**

- `MS-CUENTAS` registrado con 2 instancias `UP` (`8081` y `8082`).
- `MS-TRANSACCIONES` registrado con 1 instancia `UP` (`8083`).
- Las dos peticiones vía Gateway responden `200 OK`.

#### `P02` · Balanceo HTTP

**Precondiciones:** `ms-cuentas-1` y `ms-cuentas-2` en `UP` en Eureka.

```bash
for i in $(seq 100); do
  curl -s -o /dev/null -w '%{http_code} %header{X-Service-Instance}\n' http://localhost:8080/api/cuentas/instancia
done | sort | uniq -c
```

**Criterios de aceptación:**

- 100/100 respuestas `200`.
- Reparto equilibrado entre `ms-cuentas-1:8081` y `ms-cuentas-2:8082` (aprox. 50/50, nunca 100/0).

#### `P03` · Fallo de instancia

**Precondiciones:** tráfico periódico activo contra el Gateway.

1. En una terminal, dejar tráfico continuo y observar que responden las dos instancias:

   ```bash
   while true; do
     printf '%s ' "$(date +%T)"
     curl -s -o /dev/null --max-time 5 -w '%{http_code} %header{X-Service-Instance}\n' \
       http://localhost:8080/api/cuentas/0991112233
     sleep 0.2
   done
   ```

2. En otra terminal, detener una instancia durante la ráfaga:

   ```bash
   docker compose stop ms-cuentas-2
   ```

3. Medir los errores transitorios y el tiempo hasta que solo responde `ms-cuentas-1`.
4. Reiniciar la instancia y medir el tiempo hasta que vuelve a recibir tráfico:

   ```bash
   docker compose start ms-cuentas-2
   ```

**Criterios de aceptación:**

- Tras la ventana de detección, el sistema sigue atendiendo mediante `ms-cuentas-1`.
- Al reiniciar, `ms-cuentas-2` vuelve a registrarse en Eureka y reanuda su participación en el balanceo.

Con `use-read-only-response-cache: false` en Eureka y el reintento de `GET` ante errores de conexión en el Gateway, la convergencia es inmediata y no hay errores visibles para el cliente.

#### `P04` · Comunicación entre servicios

**Precondiciones:** cuentas `0991112233` y `0984445566` activas en `cuentas_db`.

```bash
curl -s http://localhost:8080/api/cuentas/0991112233/saldo-critico | jq '.datos.saldo'
curl -s http://localhost:8080/api/cuentas/0984445566/saldo-critico | jq '.datos.saldo'

# Caso exitoso
curl -i -X POST http://localhost:8080/api/transacciones/transferir \
  -H 'Content-Type: application/json' \
  -d '{"celularOrigen":"0991112233","celularDestino":"0984445566","monto":25.00,"motivo":"Prueba P04"}'

# Error controlado: monto mayor al saldo disponible
curl -i -X POST http://localhost:8080/api/transacciones/transferir \
  -H 'Content-Type: application/json' \
  -d '{"celularOrigen":"0991112233","celularDestino":"0984445566","monto":9999.00,"motivo":"Saldo insuficiente"}'
```

Volver a consultar los saldos después de cada transferencia.

**Criterios de aceptación:**

- Caso exitoso: `201 Created`, origen descontado, destino acreditado, transacción persistida en `tx_db.transacciones` y `auditoriaTecnica.instanciaCuentasConsultada` presente.
- Caso de error: `400` o `409` controlado sin alterar los saldos.

#### `P05` · Enrutamiento de base de datos

**Precondiciones:** `primary`, `replica1` y `replica2` sanos y 2 réplicas en `streaming`:

```bash
docker compose exec primary sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT application_name, client_addr, state FROM pg_stat_replication"'
```

1. Ejecutar una transferencia (como en `P04`) y revisar `auditoriaTecnica.nodoBaseDatos`.
2. Ejecutar 20 consultas ordinarias y contar el nodo usado:

   ```bash
   for i in $(seq 10); do
     for url in cuentas/0991112233/contactos transacciones/historial/0991112233; do
       curl -s -o /dev/null -w '%{http_code} %header{X-Db-Node}\n' "http://localhost:8080/api/$url"
     done
   done | sort | uniq -c
   curl -s http://localhost:8080/api/cuentas/0991112233/contactos | jq '.auditoriaTecnica'
   ```

3. Consultar el estado del enrutamiento y los logs:

   ```bash
   curl -s http://localhost:8080/api/cuentas/db/estado | jq
   docker compose logs --tail=30 ms-cuentas-1
   ```

**Criterios de aceptación:**

- La escritura muestra `nodoBaseDatos` en `PRIMARY` con `recovery=false`.
- Las lecturas ordinarias muestran `recovery=true` y se reparten entre `REPLICA_1` y `REPLICA_2`, cada una con su IP (`inet_server_addr()`).

#### `P06` · Fallo de réplica PostgreSQL

**Precondiciones:** ambas réplicas sanas y atendiendo lecturas.

```bash
docker compose stop replica1

for i in $(seq 10); do
  for url in cuentas/0991112233/contactos transacciones/historial/0991112233; do
    curl -s -o /dev/null -w '%{http_code} %header{X-Db-Node} fallback=%header{X-Db-Fallback}\n' \
      "http://localhost:8080/api/$url"
  done
done | sort | uniq -c

curl -s http://localhost:8080/api/cuentas/db/estado | jq '.replicas'
curl -s http://localhost:8080/api/transacciones/db/estado | jq '.replicas'
docker compose logs --tail=20 ms-cuentas-1 | grep ReplicaHealthTracker
```

**Criterios de aceptación:**

- Las consultas siguen respondiendo `200 OK` usando `REPLICA_2` (0 fallos al cliente). Las primeras pueden traer `X-Db-Fallback: true` mientras la sonda de 3 s detecta la caída.
- `/api/cuentas/db/estado` muestra `REPLICA_1` con `available=false` y `REPLICA_2` con `available=true`.

Cada instancia de `ms-cuentas` tiene su propio `ReplicaHealthTracker`; repetir la consulta de estado para ver las dos.

#### `P07` · Consistencia de lectura (*read-your-own-writes*)

**Precondiciones:** cuenta origen con saldo conocido.

```bash
CODIGO=$(curl -s -X POST http://localhost:8080/api/transacciones/transferir \
  -H 'Content-Type: application/json' \
  -d '{"celularOrigen":"0991112233","celularDestino":"0984445566","monto":25.00,"motivo":"Prueba P07"}' \
  | jq -r '.datos.codigoComprobante')

# Inmediatamente después, en peticiones secuenciales:
curl -s http://localhost:8080/api/cuentas/0991112233/saldo-critico | jq '{saldo: .datos.saldo, auditoria: .auditoriaTecnica}'
curl -s "http://localhost:8080/api/transacciones/comprobante/$CODIGO" | jq '{codigo: .datos.codigoComprobante, auditoria: .auditoriaTecnica}'

# Opcional: lectura ordinaria forzada al primario
curl -i -H 'X-Consistencia: CRITICA' http://localhost:8080/api/cuentas/0991112233
```

**Criterios de aceptación:**

- El saldo aparece ya descontado y el comprobante recién creado es visible sin esperar la propagación asíncrona.
- `auditoriaTecnica` confirma `recovery=false` (`PRIMARY`) y `politicaEnrutamiento = LECTURA_CRITICA_PRIMARIO`.

#### `P08` · Recuperación de réplica

**Precondiciones:** `replica1` detenida tras `P06` y con escrituras nuevas generadas mientras estuvo caída (por ejemplo, la transferencia de `P07`).

```bash
docker compose start replica1

docker compose exec primary sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT application_name, state, sent_lsn, replay_lsn FROM pg_stat_replication"'

# Repetir hasta ver 2 sondeos exitosos y available=true
curl -s http://localhost:8080/api/cuentas/db/estado | jq '.replicas[] | {nodo, available, consecutiveSuccesses, lastReplayLsn}'
```

Después, repetir las 20 lecturas ordinarias de `P05` y comprobar que `REPLICA_1` vuelve a aparecer y a incrementar su contador en `consultasTotales`.

**Criterios de aceptación:**

- `replica1` sincroniza los WAL pendientes (`state = streaming`, `replay_lsn` igual a `sent_lsn`).
- Supera los 2 chequeos `pg_is_in_recovery() = true` y vuelve a participar en el *Round-Robin*.

La recuperación depende de que los WAL necesarios sigan disponibles en el primario. `wal_keep_size` fija una retención mínima, pero no la garantiza indefinidamente; en producción se usarían *replication slots* y archivado de WAL.

### Limpieza

```bash
docker compose down      # detiene los contenedores y conserva los datos
docker compose down -v   # borra también los volúmenes (migraciones y datos semilla se reaplican al levantar)
```
