# 3.2 Requisitos Funcionales — Microservicio de Transacciones (`ms-transacciones`)

---

### `RF-06` · Orquestación de Transferencia P2P mediante Descubrimiento Dinámico
- **Prioridad:** Crítica
- **Servicio propietario:** `ms-transacciones` (`POST /api/transacciones/transferir`)
- **Descripción:** El sistema debe recibir solicitudes de transferencia P2P (`celularOrigen`, `celularDestino`, `monto`, `motivo`), validar los datos de entrada y delegar el débito/crédito a `ms-cuentas` exclusivamente mediante descubrimiento dinámico por nombre lógico (`http://ms-cuentas/api/cuentas/movimiento-interno`), persistiendo el movimiento en el libro mayor (`tx_db.transacciones`).
- **Política de persistencia:** `@UsarNodo(TipoNodo.PRIMARY)`.
- **Criterios de aceptación:**
  1. Genera un identificador único de comprobante (ej. `TX-2026-XXXX`).
  2. Invoca a `lb://ms-cuentas` usando `RestClient` con `@LoadBalanced`.
  3. Si `ms-cuentas` responde `200 OK`, registra la transacción con `estado = EXITOSA` en `tx_db.transacciones` (Primario) y retorna `HTTP 201 Created` con `auditoriaTecnica` incluyendo `servicioOrigen` e `instanciaCuentasConsultada`.
  4. Si `ms-cuentas` rechaza por regla de negocio (`400`/`409`, ej. saldo insuficiente), registra la transacción con `estado = RECHAZADA` (o devuelve el error de negocio controlado sin alterar saldos) y propaga un mensaje claro al cliente.
  5. Si `ms-cuentas` no tiene instancias disponibles, retorna `HTTP 503 Service Unavailable` con detalle controlado.

---

### `RF-07` · Consulta de Historial de Movimientos por Celular
- **Prioridad:** Crítica
- **Servicio propietario:** `ms-transacciones` (`GET /api/transacciones/historial/{celular}`)
- **Descripción:** El sistema debe listar las transacciones históricas donde el número celular participe como origen o destino, ordenadas cronológicamente de la más reciente a la más antigua.
- **Política de persistencia:** `@UsarNodo(TipoNodo.REPLICA)` distribuida por *Round-Robin* entre `REPLICA_1` y `REPLICA_2`.
- **Criterios de aceptación:**
  1. Retorna `HTTP 200 OK` con el listado de movimientos y `auditoriaTecnica.nodoBaseDatos` apuntando a una réplica (`recovery=true`).
  2. No impacta al nodo Primario durante consultas repetitivas de historial.

---

### `RF-08` · Verificación Crítica de Comprobante Recién Generado
- **Prioridad:** Crítica
- **Servicio propietario:** `ms-transacciones` (`GET /api/transacciones/comprobante/{codigo}`)
- **Descripción:** El sistema debe permitir validar de forma inmediata el estado y detalle de un comprobante (`codigo_comprobante`) recién emitido tras una transferencia.
- **Política de persistencia:** `@UsarNodo(TipoNodo.PRIMARY)`.
- **Criterios de aceptación:**
  1. Consulta directamente `postgres-primary` (`recovery=false`, `politicaEnrutamiento = LECTURA_CRITICA_PRIMARIO`).
  2. Si el comprobante existe, retorna `HTTP 200 OK`; si no existe, `HTTP 404 Not Found`.

---

### `RF-09` · Observabilidad del Estado de Réplicas por Microservicio
- **Prioridad:** Alta
- **Servicio propietario:** Ambos (`GET /api/cuentas/db/estado` y `GET /api/transacciones/db/estado` vía Gateway, mapeados a `/api/db/estado`)
- **Descripción:** Cada microservicio debe exponer un endpoint de diagnóstico que muestre en tiempo real el estado de disponibilidad de `REPLICA_1` y `REPLICA_2`, último LSN reproducido, conteo de consultas servidas en `PRIMARY`, `REPLICA_1` y `REPLICA_2`, y errores recientes.
- **Criterios de aceptación:**
  1. Permite comprobar cuantitativamente el reparto de consultas en P05, el paso a `available=false` en P06 y la reincorporación a `available=true` en P08.
