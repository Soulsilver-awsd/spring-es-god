# Pruebas de replicación PostgreSQL

## 1. Objetivo

Validar el funcionamiento de una infraestructura PostgreSQL compuesta por un nodo primario y dos réplicas de lectura, desplegados mediante Docker Compose.

Las pruebas permiten verificar:

- El estado de los nodos.
- La replicación de datos mediante WAL.
- La separación de operaciones de lectura y escritura.
- La continuidad del servicio ante la caída de una réplica.
- La recuperación y sincronización de una réplica después de reiniciarse.

## 2. Requisitos previos

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

## 3. Prueba 1: identificar el rol de cada nodo

### Nodo primario

```bash
docker compose exec primary \
  psql -U admin -d laboratorio \
  -c "SELECT pg_is_in_recovery();"
```

**Resultado esperado:** `false` (`f`).

Esto significa que PostgreSQL no se encuentra en modo de recuperación y funciona como primario.

### Réplica 1

```bash
docker compose exec replica1 \
  psql -U admin -d laboratorio \
  -c "SELECT pg_is_in_recovery();"
```

**Resultado esperado:** `true` (`t`).

### Réplica 2

```bash
docker compose exec replica2 \
  psql -U admin -d laboratorio \
  -c "SELECT pg_is_in_recovery();"
```

**Resultado esperado:** `true` (`t`).

Ambas instancias funcionan como servidores standby.

## 4. Prueba 2: verificar el streaming WAL

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

### Interpretación

`sent_lsn` indica hasta qué posición WAL ha enviado el primario.

`replay_lsn` indica hasta qué posición la réplica ha reproducido los cambios, según la información reportada al primario.

Una diferencia entre estas posiciones puede indicar retraso de replicación.

## 5. Prueba 3: crear información en el primario

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

## 6. Prueba 4: verificar datos en las réplicas

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

## 7. Prueba 5: impedir escrituras en una réplica

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

## 8. Prueba 6: simular la caída de una réplica

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

## 9. Prueba 7: generar cambios mientras una réplica está detenida

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

## 10. Prueba 8: recuperar la réplica detenida

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

### Advertencia técnica

La recuperación depende de que los WAL necesarios sigan disponibles.

El parámetro `wal_keep_size` establece una retención mínima, pero no garantiza conservar indefinidamente todos los registros WAL.

En sistemas de producción pueden utilizarse slots de replicación y archivado WAL, junto con mecanismos de monitoreo y control del almacenamiento.

## 11. Prueba 9: comprobar el estado final de replicación

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

## 12. Preguntas para el análisis técnico

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

## 13. Evidencias de funcionamiento

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

## 14. Limpieza del laboratorio

Para detener los contenedores sin eliminar los volúmenes:

```bash
docker compose down
```

Para eliminar los contenedores y los volúmenes asociados:

```bash
docker compose down -v
```

**Advertencia:** `down -v` elimina los datos persistidos en los volúmenes Docker del proyecto. Utilizar únicamente cuando se desee reiniciar completamente el laboratorio.