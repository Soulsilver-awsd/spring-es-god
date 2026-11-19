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

## Verificación P01–P08

Los 8 escenarios de [criterios de aceptación](docs/srs/06-verificacion-y-trazabilidad/01-criterios-aceptacion-p01-p08.md) están automatizados solo con `curl`, con aserciones y un resumen final (código de salida `0` si todo pasa):

```bash
./docs/api/curl-p01-p08.sh            # Linux / macOS / WSL
./docs/api/curl-p01-p08.sh P03 P06    # solo algunas pruebas
```

```powershell
.\docs\api\curl-p01-p08.ps1           # Windows PowerShell
.\docs\api\curl-p01-p08.ps1 P03 P06
```

| Prueba | Qué hace el script | Criterio |
|---|---|---|
| `P01` | `GET :8761/eureka/apps` + lecturas vía `:8080` | `MS-CUENTAS` 2 `UP`, `MS-TRANSACCIONES` 1 `UP`, `200` vía Gateway |
| `P02` | 120 × `GET /api/cuentas/instancia` contando `X-Service-Instance` | 120/120 `200`, reparto ~60/60 |
| `P03` | Tráfico continuo + `docker compose stop ms-cuentas-2` y luego `start` | Convergencia a `ms-cuentas-1` y reincorporación de `ms-cuentas-2` |
| `P04` | Transferencia de `25.00` + intento de `9999.00` | `201` con `instanciaCuentasConsultada`; `409` sin alterar saldos |
| `P05` | Escritura + 20 lecturas ordinarias + `/api/cuentas/db/estado` | Escritura en `PRIMARY`; lecturas repartidas `REPLICA_1`/`REPLICA_2` |
| `P06` | `docker compose stop replica1` + 20 lecturas | 0 errores HTTP; `REPLICA_1 available=false` |
| `P07` | Transferencia + `saldo-critico` + `comprobante/{codigo}` inmediatos | `LECTURA_CRITICA_PRIMARIO`, `recovery=false`, saldo exacto |
| `P08` | `docker compose start replica1` + sondeo de `/db/estado` + 20 lecturas | `available=true` tras 2/2 sondeos y vuelta al *Round-Robin* |

`P03`, `P06` y `P08` detienen y arrancan contenedores y los dejan en su estado inicial. `P04`, `P05`, `P07` y `P08` hacen transferencias reales: tras unas 6 ejecuciones completas se agota el límite diario de `0991112233` (`300.00`) y hay que reiniciar con `docker compose down -v`.

La evidencia de una ejecución completa está en [docs/api/evidencia-p01-p08.md](docs/api/evidencia-p01-p08.md).

## Anexo · Laboratorio de replicación PostgreSQL

### 1. Objetivo

Validar el funcionamiento de una infraestructura PostgreSQL compuesta por un nodo primario y dos réplicas de lectura, desplegados mediante Docker Compose.

Las pruebas permiten verificar:

- El estado de los nodos.
- La replicación de datos mediante WAL.
- La separación de operaciones de lectura y escritura.
- La continuidad del servicio ante la caída de una réplica.
- La recuperación y sincronización de una réplica después de reiniciarse.

### 2. Requisitos previos

Tener Docker y Docker Compose instalados.

Ejecutar todos los comandos desde el directorio que contiene `docker-compose.yml`.

Iniciar los contenedores:

```bash
docker compose up -d
```

Verificar su estado:

```bash
docker compose ps
```

Deben aparecer los servicios `primary`, `replica1` y `replica2`.

> Los comandos utilizan el usuario `admin` y la base de datos `laboratorio`, definidos en el ejemplo. Adaptarlos si se modifica la configuración.

### 3. Prueba 1: identificar el rol de cada nodo

#### Nodo primario

```bash
docker compose exec primary \
  psql -U admin -d laboratorio \
  -c "SELECT pg_is_in_recovery();"
```

**Resultado esperado:** `false` (`f`).

Esto significa que PostgreSQL no se encuentra en modo de recuperación y funciona como primario.

#### Réplica 1

```bash
docker compose exec replica1 \
  psql -U admin -d laboratorio \
  -c "SELECT pg_is_in_recovery();"
```

**Resultado esperado:** `true` (`t`).

#### Réplica 2

```bash
docker compose exec replica2 \
  psql -U admin -d laboratorio \
  -c "SELECT pg_is_in_recovery();"
```

**Resultado esperado:** `true` (`t`).

Ambas instancias funcionan como servidores standby.

### 4. Prueba 2: verificar el streaming WAL

Ejecutar en el primario:

```bash
docker compose exec primary \
  psql -U admin -d laboratorio \
  -c "SELECT application_name,
             client_addr,
             state,
             sync_state,
             sent_lsn,
             replay_lsn
      FROM pg_stat_replication;"
```

**Resultado esperado:**

- Dos conexiones correspondientes a las réplicas.
- `state = streaming`.
- `sync_state = async` en la configuración propuesta.
- Valores LSN que representan posiciones del registro WAL.

#### Interpretación

`sent_lsn` indica hasta qué posición WAL ha enviado el primario.

`replay_lsn` indica hasta qué posición la réplica ha reproducido los cambios, según la información reportada al primario.

Una diferencia entre estas posiciones puede indicar retraso de replicación.

### 5. Prueba 3: crear información en el primario

Crear una tabla:

```bash
docker compose exec primary \
  psql -U admin -d laboratorio \
  -c "CREATE TABLE IF NOT EXISTS prueba_replica (
        id BIGSERIAL PRIMARY KEY,
        mensaje TEXT NOT NULL,
        fecha TIMESTAMPTZ DEFAULT NOW()
      );"
```

Insertar un registro:

```bash
docker compose exec primary \
  psql -U admin -d laboratorio \
  -c "INSERT INTO prueba_replica (mensaje)
      VALUES ('Hola desde el nodo primario');"
```

Consultar el primario:

```bash
docker compose exec primary \
  psql -U admin -d laboratorio \
  -c "SELECT * FROM prueba_replica;"
```

**Resultado esperado:** aparece el registro insertado.

### 6. Prueba 4: verificar datos en las réplicas

Consultar la réplica 1:

```bash
docker compose exec replica1 \
  psql -U admin -d laboratorio \
  -c "SELECT * FROM prueba_replica;"
```

Consultar la réplica 2:

```bash
docker compose exec replica2 \
  psql -U admin -d laboratorio \
  -c "SELECT * FROM prueba_replica;"
```

**Resultado esperado:** ambas réplicas muestran el registro creado en el primario una vez reproducidos los WAL.

Esto demuestra que los cambios se propagan desde el primario hacia los nodos secundarios.

> La replicación es asíncrona. Si una consulta se realiza inmediatamente después de una escritura, podría existir un retraso temporal.

### 7. Prueba 5: impedir escrituras en una réplica

Intentar insertar directamente en `replica1`:

```bash
docker compose exec replica1 \
  psql -U admin -d laboratorio \
  -c "INSERT INTO prueba_replica (mensaje)
      VALUES ('Escritura no permitida');"
```

**Resultado esperado:**

```text
ERROR: cannot execute INSERT in a read-only transaction
```

El error es el comportamiento correcto.

Las réplicas físicas en modo standby no permiten modificar directamente los datos.

### 8. Prueba 6: simular la caída de una réplica

Detener `replica1`:

```bash
docker compose stop replica1
```

Verificar el estado:

```bash
docker compose ps
```

Comprobar que el primario continúa funcionando:

```bash
docker compose exec primary \
  psql -U admin -d laboratorio \
  -c "SELECT COUNT(*) FROM prueba_replica;"
```

Comprobar que la segunda réplica sigue disponible:

```bash
docker compose exec replica2 \
  psql -U admin -d laboratorio \
  -c "SELECT COUNT(*) FROM prueba_replica;"
```

**Resultado esperado:** el primario y `replica2` continúan atendiendo sus consultas.

### 9. Prueba 7: generar cambios mientras una réplica está detenida

Con `replica1` detenida, insertar 100 registros:

```bash
docker compose exec primary \
  psql -U admin -d laboratorio \
  -c "INSERT INTO prueba_replica (mensaje)
      SELECT 'Registro de recuperación ' || g
      FROM generate_series(1,100) AS g;"
```

Consultar el número de registros de la prueba:

```bash
docker compose exec primary \
  psql -U admin -d laboratorio \
  -c "SELECT COUNT(*)
      FROM prueba_replica
      WHERE mensaje LIKE 'Registro de recuperación %';"
```

**Resultado esperado:** 100 registros nuevos, siempre que la prueba se ejecute una sola vez.

Verificar que `replica2` recibió los cambios:

```bash
docker compose exec replica2 \
  psql -U admin -d laboratorio \
  -c "SELECT COUNT(*)
      FROM prueba_replica
      WHERE mensaje LIKE 'Registro de recuperación %';"
```

Si la réplica ya está sincronizada, también devolverá 100.

### 10. Prueba 8: recuperar la réplica detenida

Reiniciar el servicio:

```bash
docker compose start replica1
```

Consultar sus logs:

```bash
docker compose logs --tail=50 replica1
```

Esperar hasta que PostgreSQL acepte conexiones de lectura.

Verificar los registros:

```bash
docker compose exec replica1 \
  psql -U admin -d laboratorio \
  -c "SELECT COUNT(*)
      FROM prueba_replica
      WHERE mensaje LIKE 'Registro de recuperación %';"
```

**Resultado esperado:** 100 registros.

La réplica recuperó los cambios generados mientras estuvo detenida.

#### Advertencia técnica

La recuperación depende de que los WAL necesarios sigan disponibles.

El parámetro `wal_keep_size` establece una retención mínima, pero no garantiza conservar indefinidamente todos los registros WAL.

En sistemas de producción pueden utilizarse slots de replicación y archivado WAL, junto con mecanismos de monitoreo y control del almacenamiento.

### 11. Prueba 9: comprobar el estado final de replicación

Ejecutar nuevamente:

```bash
docker compose exec primary \
  psql -U admin -d laboratorio \
  -c "SELECT application_name,
             state,
             sync_state,
             sent_lsn,
             replay_lsn
      FROM pg_stat_replication;"
```

**Resultado esperado:** las dos réplicas vuelven a aparecer con `state = streaming`.

Para confirmar que están al día, comparar sus posiciones de reproducción con la posición WAL del primario y comprobar los registros de prueba.

### 12. Preguntas para el análisis técnico

1. ¿Cuál es la diferencia entre un nodo primario y una réplica?
2. ¿Qué función cumple el WAL?
3. ¿Qué significa `pg_is_in_recovery()`?
4. ¿Por qué no podemos insertar registros directamente en una réplica física?
5. ¿Qué ocurre con las escrituras cuando una réplica deja de funcionar?
6. ¿Qué sucede cuando el primario deja de funcionar?
7. ¿Qué diferencia existe entre replicación y alta disponibilidad?
8. ¿Qué riesgos introduce la replicación asíncrona?
9. ¿Por qué es importante conservar los WAL durante una interrupción?
10. ¿Cómo podría una aplicación distribuir consultas entre varias réplicas?

### 13. Evidencias de funcionamiento

El informe técnico debe incluir:

- Captura o salida de `docker compose ps`.
- Identificación del primario y de las réplicas.
- Resultado de `pg_stat_replication`.
- Inserción de información en el primario.
- Lectura de la información desde ambas réplicas.
- Error esperado al intentar escribir en una réplica.
- Evidencia de la detención de una réplica.
- Inserción de 100 registros durante la interrupción.
- Recuperación y sincronización posterior.
- Explicación técnica de los resultados.

### 14. Limpieza del laboratorio

Para detener los contenedores sin eliminar los volúmenes:

```bash
docker compose down
```

Para eliminar los contenedores y los volúmenes asociados:

```bash
docker compose down -v
```

**Advertencia:** `down -v` elimina los datos persistidos en los volúmenes Docker del proyecto. Utilizar únicamente cuando se desee reiniciar completamente el laboratorio.