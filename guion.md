# Guion de Presentación Técnica · Billetera Digital Distribuida

**Duración estimada:** 8 a 10 minutos  
**Herramienta de soporte:** Terminal interactiva `presentacion.sh`  
**Objetivo:** Demostrar arquitectura desacoplada, consistencia ACID, enrutamiento primario/réplicas y tolerancia a fallos en vivo sin salir de la terminal.

---

## 1. Preparación previa (fuera de cámara)

1. Levantar el clúster desde cero con datos limpios:
   ```bash
   docker compose down -v && docker compose up -d --build
   ```
2. Verificar que los 8 contenedores reporten estado `healthy`:
   ```bash
   docker inspect --format '{{.Name}}: {{.State.Health.Status}}' $(docker compose ps -q)
   ```
3. Iniciar la presentación interactiva en una terminal maximizada (mínimo 80 columnas):
   ```bash
   ./presentacion.sh
   ```

> **Controles rápidos de `presentacion.sh`:**
> - `[ESPACIO]` o `[→]`: Avanzar diapositiva / Siguiente fase de prueba.
> - `[←]`: Retroceder diapositiva.
> - `[R]`: Refrescar la prueba de la diapositiva actual.
> - `[E]`: Exportar el reporte Markdown completo con evidencias HTTP.
> - `[Q]`: Salir de la presentación.

---

## 2. Cronograma y reparto de tiempos

| Bloque | Slides | Tema principal | Tiempo sugerido |
|---|---|---|---|
| **Bloque 1** | 01 – 02 | Arquitectura, Topología y Clúster Docker | 1:00 min |
| **Bloque 2** | 03 – 04 | Service Discovery (Eureka) y Balanceo Round Robin | 1:15 min |
| **Bloque 3** | 05 – 06 | Orquestación P2P, Transacciones ACID y Validaciones | 1:30 min |
| **Bloque 4** | 07 – 08 | Replicación PostgreSQL (WAL) y Consistencia RYOW | 1:30 min |
| **Bloque 5** | 09 – 14 | Resiliencia en Vivo: Caída de Instancia y de Réplica | 2:15 min |
| **Bloque 6** | 15 | Conclusiones, Trade-offs y Exportación | 1:00 min |
| **Total** | | | **~8:30 min** |

---

## 3. Guion diapositiva por diapositiva

### Bloque 1: Arquitectura y Clúster

#### Slide 01 · Arquitectura del Sistema (8 Contenedores Docker) ~ 35s
* **En pantalla:** Diagrama C4 de contenedores y capas en la terminal.
* **Acción:** `[ESPACIO]` para continuar tras explicar.
* **Guion del presentador:**
  > "Presentamos una billetera digital distribuida P2P ejecutada sobre 8 contenedores Docker independientes. La arquitectura se basa en el principio de estricto desacoplamiento: tenemos dos microservicios de negocio (`ms-cuentas` y `ms-transacciones`), cada uno con su propio esquema y credenciales en base de datos. Ningún servicio accede directamente a las tablas del otro. Todo el tráfico externo entra centralizado a través de un API Gateway en el puerto 8080."
* **Puntos clave:** Destacar la segregación *Database-per-Service* y la ausencia de acoplamiento físico directo entre clientes y servicios.

#### Slide 02 · Clúster Docker Compose (Estado de Servicios) ~ 25s
* **En pantalla:** Tabla en vivo con los 8 contenedores y su salud.
* **Acción:** `[ESPACIO]` para avanzar.
* **Guion del presentador:**
  > "Verificamos la topología en tiempo real: Eureka Server para descubrimiento, API Gateway, dos instancias de cuentas (`ms-cuentas-1` y `ms-cuentas-2`) para balanceo y alta disponibilidad, `ms-transacciones`, y un clúster PostgreSQL 17 compuesto por un primario de escritura y dos réplicas sincronizadas mediante streaming físico de registros WAL. Todos los servicios reportan estado healthy."

---

### Bloque 2: Descubrimiento y Balanceo HTTP

#### Slide 03 · Descubrimiento Dinámico con Netflix Eureka ~ 35s
* **En pantalla:** Catálogo consultado en vivo desde `:8761/eureka/apps`.
* **Acción:** `[ESPACIO]` para avanzar.
* **Guion del presentador:**
  > "En arquitecturas dinámicas no se configuran direcciones IP fijas. Cada microservicio se registra automáticamente en Eureka al inicializar y envía un latido (heartbeat) cada 5 segundos. El API Gateway resuelve dinámicamente las rutas utilizando el identificador lógico `lb://ms-cuentas`. Esto permite añadir o reemplazar réplicas de cómputo de manera transparente."

#### Slide 04 · Balanceo de Carga HTTP (Round Robin) ~ 40s
* **En pantalla:** Ejecución de 20 peticiones `GET /api/cuentas/instancia` con reparto 10/10.
* **Acción:** `[ESPACIO]` para lanzar la ráfaga y avanzar.
* **Guion del presentador:**
  > "Lanzamos una ráfaga de 20 peticiones concurrentes al endpoint `/api/cuentas/instancia`. En la cabecera `X-Service-Instance` observamos un reparto equitativo 10/10 entre la instancia 8081 y la 8082 mediante Round Robin en capa 7. Los microservicios son totalmente stateless, permitiendo distribuir carga sin afinidad de sesión."

---

### Bloque 3: Comunicación P2P y Transaccionalidad ACID

#### Slide 05 · Orquestación P2P entre Microservicios (ACID) ~ 50s
* **En pantalla:** Transferencia exitosa de $25.00 con comprobante generado (`HTTP 201`).
* **Acción:** `[ESPACIO]` para ejecutar la transferencia.
* **Guion del presentador:**
  > "Ejecutamos una transferencia P2P de $25. El cliente invoca a `ms-transacciones`, pero este delega el movimiento contable en `ms-cuentas` resolviéndolo por Eureka. Dentro de `ms-cuentas`, débito y crédito se ejecutan en una única transacción ACID. Para prevenir deadlocks por concurrencia, aplicamos bloqueo pesimista ordenando las cuentas por su identificador numérico. La auditoría técnica confirma que la escritura se canalizó obligatoriamente al nodo primario de la base de datos."
* **Puntos clave:** Señalar `instanciaCuentasConsultada` y `nodoBaseDatos: PRIMARY (recovery=false)`.

#### Slide 06 · Validación de Reglas de Negocio (Error Controlado) ~ 40s
* **En pantalla:** Rechazo controlado de transferencia de $9999.00 (`HTTP 409`).
* **Acción:** `[ESPACIO]` para avanzar.
* **Guion del presentador:**
  > "Probamos ahora una solicitud que excede el saldo disponible. El servicio responde un error controlado `409 Conflict`. La transacción es revertida en su totalidad preservando la integridad del saldo, mientras que en `ms-transacciones` queda auditado el comprobante con estado `RECHAZADA` para garantizar trazabilidad financiera completa."

---

### Bloque 4: Persistencia Replicada y Consistencia

#### Slide 07 · Enrutamiento BD: Primario vs Réplicas WAL ~ 45s
* **En pantalla:** 20 lecturas ordinarias (`contactos` e `historial`) distribuidas en réplicas.
* **Acción:** `[ESPACIO]` para ejecutar las lecturas.
* **Guion del presentador:**
  > "El sistema implementa un `RoutingDataSource` dinámico. Las escrituras van siempre al primario, pero las lecturas ordinarias que toleran consistencia eventual se desvían a las réplicas PostgreSQL. Las 20 peticiones se reparten equitativamente entre `REPLICA_1` y `REPLICA_2` (ambas con `recovery=true`), descargando al primario del tráfico masivo de lectura."

#### Slide 08 · Consistencia Inmediata: Read-Your-Own-Writes (RYOW) ~ 45s
* **En pantalla:** Consulta a `/api/cuentas/{origen}/saldo-critico` resuelta en `PRIMARY` (`HTTP 200`).
* **Acción:** `[ESPACIO]` para ejecutar la consulta.
* **Guion del presentador:**
  > "La replicación asíncrona por WAL introduce un retardo mínimo (lag de replicación). Si un usuario realiza una transferencia y consulta inmediatamente su saldo, una réplica podría devolver un dato desactualizado. Para mitigar esto, diseñamos el endpoint de saldo crítico con la política Read-Your-Own-Writes, forzando la lectura directa en el nodo primario para garantizar consistencia inmediata."

---

### Bloque 5: Tolerancia a Fallos y Alta Disponibilidad

#### Slide 09 · Alta Disponibilidad HTTP: Caída de `ms-cuentas-2` ~ 50s
* **En pantalla:** Telemetría en vivo con ráfaga continua contra el Gateway.
* **Acción:**
  1. `[ESPACIO]` para detener `ms-cuentas-2`. Observar convergencia a `ms-cuentas-1`.
  2. `[ESPACIO]` para reiniciar `ms-cuentas-2`. Observar su reincorporación tras el arranque JVM.
  3. `[ESPACIO]` para ver el resumen y continuar.
* **Guion del presentador:**
  > "Iniciamos tráfico continuo contra el sistema y forzamos la caída súbita de `ms-cuentas-2`. El Gateway y Eureka detectan la degradación y en menos de 400 milisegundos convergen el 100% del tráfico a `ms-cuentas-1`, registrando cero errores 5xx de cara al usuario. Al reiniciar el contenedor, el sistema espera su calentamiento antes de reintegrarlo al pool de Round Robin."

#### Slide 10 · Introducción al Fallo en la Capa de Datos ~ 20s
* **En pantalla:** Diagrama de clúster PostgreSQL y concepto de pérdida de réplica.
* **Acción:** `[ESPACIO]` para avanzar.
* **Guion del presentador:**
  > "Trasladamos ahora la prueba de fallos a la capa de persistencia. Analizaremos qué ocurre con las consultas activas cuando una de las réplicas físicas de PostgreSQL queda fuera de servicio."

#### Slide 11 · Failover Transparente: Lecturas sobre `REPLICA_2` ~ 40s
* **En pantalla:** `docker compose stop replica1` y ejecución de 20 lecturas exitosas en `REPLICA_2`.
* **Acción:** `[ESPACIO]` para detener la réplica y lanzar las consultas.
* **Guion del presentador:**
  > "Detenemos `replica1` en caliente. El pool de conexiones intercepta la indisponibilidad y redirige automáticamente las 20 lecturas ordinarias a `replica2`. Ninguna solicitud falló; el cliente recibe respuestas 200 transparentes a pesar de haber perdido la mitad del clúster de lectura."

#### Slide 12 · Detección Automática de Réplicas (Health Tracker) ~ 25s
* **En pantalla:** Consulta a `/api/cuentas/db/estado` mostrando `REPLICA_1` en `available: false`.
* **Acción:** `[ESPACIO]` para consultar el estado.
* **Guion del presentador:**
  > "Un componente interno denominado `ReplicaHealthTracker` sondea cada 3 segundos la función `pg_is_in_recovery()`. Al registrar el fallo, marca la réplica como no disponible y la remueve del algoritmo de selección para no degradar la latencia."

#### Slide 13 · Recuperación y Sincronización WAL ~ 20s
* **En pantalla:** Reinicio de `replica1` y sincronización en segundo plano.
* **Acción:** `[ESPACIO]` para encender el contenedor.
* **Guion del presentador:**
  > "Reiniciamos `replica1`. Al levantar, PostgreSQL restablece el enlace de replicación por streaming con el primario y aplica de inmediato los registros WAL acumulados durante el periodo de desconexión."

#### Slide 14 · Reincorporación Automática con Umbral 2/2 ~ 30s
* **En pantalla:** Estado `/db/estado` confirmando `available: true` para ambas réplicas.
* **Acción:** `[ESPACIO]` para consultar reincorporación.
* **Guion del presentador:**
  > "Para evitar fluctuaciones transitorias (*flapping*), el enrutador no reincorpora el nodo al primer pulso de vida. Exige un umbral estricto de 2 chequeos de salud consecutivos saludables (2 x 3s) antes de habilitarlo nuevamente para recibir tráfico productivo."

---

### Bloque 6: Síntesis y Cierre

#### Slide 15 · Conclusiones, Decisiones y Mejoras ~ 50s
* **En pantalla:** Cuadro comparativo de Decisiones, Limitaciones y Mejoras Futuras.
* **Acción:**
  1. Explicar las 3 columnas.
  2. Pulsar **`[E]`** para exportar el reporte final de la sesión.
* **Guion del presentador:**
  > "En conclusión, logramos una arquitectura tolerante a fallos tanto en capa de aplicación como en persistencia.
  > - **Decisión clave:** Separación explícita de lecturas críticas al primario y consultas masivas en réplicas.
  > - **Limitación técnica:** El failover automático actual aplica únicamente a réplicas de lectura; la promoción del primario requeriría un orquestador como Patroni.
  > - **Mejora futura:** Incorporar el patrón Outbox transaccional y claves de idempotencia en transferencias.
  > Para cerrar, pulsamos la tecla 'E' para exportar el reporte forense Markdown con todas las trazas HTTP capturadas durante la sesión."

---

## 4. Evidencia generada

Al presionar **`[E]`**, `presentacion.sh` almacena un archivo Markdown en la carpeta `reportes/`:
- `reportes/reporte-YYYYMMDD-HHMMSS.md`

El reporte incluye:
1. Resumen de salud del clúster al momento de la prueba.
2. Matriz de resultados por diapositiva.
3. Trazas HTTP completas (método, URL, cabeceras técnicas, payload JSON y cuerpo de respuesta).
4. Bitácora de eventos con marcas de tiempo precisas para auditoría académica o técnica.
