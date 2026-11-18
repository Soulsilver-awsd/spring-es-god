# 3.1 Requisitos Funcionales — Microservicio de Cuentas (`ms-cuentas`)

---

### `RF-01` · Consulta Ordinaria de Perfil y Saldo de Cuenta
- **Prioridad:** Crítica
- **Servicio propietario:** `ms-cuentas` (`GET /api/cuentas/{celular}`)
- **Descripción:** El sistema debe permitir consultar los datos básicos de una billetera (titular, número celular, saldo visible, límite diario, consumido hoy y estado) a partir de su `numero_celular`.
- **Política de persistencia:** Enrutada a réplicas (`@UsarNodo(TipoNodo.REPLICA)`), salvo que el cliente envíe el encabezado `X-Consistencia: CRITICA`.
- **Criterios de aceptación:**
  1. Si el celular existe, retorna `HTTP 200 OK` con `ApiResponse<CuentaDto>` y `auditoriaTecnica` indicando la instancia (`ms-cuentas-1` o `ms-cuentas-2`) y el nodo PostgreSQL real (`replica1` / `replica2`, `recovery=true`).
  2. Si el celular no existe, retorna `HTTP 404 Not Found` con mensaje descriptivo.

---

### `RF-02` · Consulta de Contactos Frecuentes
- **Prioridad:** Alta
- **Servicio propietario:** `ms-cuentas` (`GET /api/cuentas/{celular}/contactos`)
- **Descripción:** El sistema debe devolver la lista de contactos frecuentes asociados a una cuenta propietaria para agilizar transferencias P2P.
- **Política de persistencia:** `@UsarNodo(TipoNodo.REPLICA)` distribuida en *Round-Robin* entre `REPLICA_1` y `REPLICA_2`.
- **Criterios de aceptación:**
  1. Retorna `HTTP 200 OK` con arreglo de contactos (`celularContacto`, `alias`).
  2. Si la cuenta no existe, retorna `HTTP 404 Not Found`.

---

### `RF-03` · Consulta Crítica de Saldo Inmediato (*Read-Your-Own-Writes*)
- **Prioridad:** Crítica
- **Servicio propietario:** `ms-cuentas` (`GET /api/cuentas/{celular}/saldo-critico`)
- **Descripción:** El sistema debe ofrecer una operación dedicada de lectura crítica que garantice la visualización exacta del saldo inmediatamente después de ejecutar una transferencia o abono, eliminando el riesgo de leer datos obsoletos por retraso WAL.
- **Política de persistencia:** `@UsarNodo(TipoNodo.PRIMARY)` obligatorio.
- **Criterios de aceptación:**
  1. La consulta se ejecuta en `postgres-primary` (`pg_is_in_recovery() == false`).
  2. El campo `auditoriaTecnica.politicaEnrutamiento` reporta `LECTURA_CRITICA_PRIMARIO` y `nodoBaseDatos` muestra la IP del contenedor Primario.
  3. Refleja al instante cualquier débito o crédito recién confirmado.

---

### `RF-04` · Movimiento Interno Atómico (Débito y Crédito entre Cuentas)
- **Prioridad:** Crítica
- **Servicio propietario:** `ms-cuentas` (`POST /api/cuentas/movimiento-interno`)
- **Descripción:** El sistema debe procesar movimientos internos solicitados por `ms-transacciones` para transferir un `monto` desde `celularOrigen` hacia `celularDestino` dentro de una única transacción ACID en el nodo Primario.
- **Política de persistencia:** `@UsarNodo(TipoNodo.PRIMARY)` + `@Transactional`.
- **Reglas de negocio obligatorias:**
  1. `monto` debe ser estrictamente mayor que `0` (`> 0.00`).
  2. `celularOrigen` y `celularDestino` deben ser distintos.
  3. Ambas cuentas deben existir y tener estado `ACTIVA` (si alguna está `BLOQUEADA`, rechazar con `HTTP 409 Conflict`).
  4. La cuenta origen debe disponer de fondos suficientes (`saldo >= monto`); caso contrario retornar `HTTP 400 Bad Request` / `409 Conflict` (`"Saldo insuficiente"`).
  5. La transferencia no debe superar el cupo diario (`consumido_hoy + monto <= limite_diario`); caso contrario rechazar con `HTTP 409 Conflict` (`"Límite diario excedido"`).
  6. Deben actualizarse ambas cuentas (restar `monto` y sumar `consumido_hoy` en origen; sumar `monto` en destino) en orden determinístico de bloqueo para prevenir *deadlocks*.
- **Criterios de aceptación:**
  1. Retorna `HTTP 200 OK` con `nuevoSaldoOrigen`, `nuevoSaldoDestino` e identificación exacta de la instancia `ms-cuentas-X` que atendió la llamada.
  2. Ante cualquier fallo de validación, ninguna cuenta ve alterado su saldo.

---

### `RF-05` · Alta de Billetera y Diagnóstico de Instancia
- **Prioridad:** Media
- **Servicio propietario:** `ms-cuentas` (`POST /api/cuentas`, `GET /api/cuentas/instancia`)
- **Descripción:** Permitir registrar nuevas cuentas de prueba en `PRIMARY` y exponer un endpoint liviano `/instancia` que responda desde `REPLICA` para ejecutar las 100+ solicitudes de balanceo HTTP (P02) y pruebas de caída de instancia (P03).
- **Criterios de aceptación:**
  1. `POST /api/cuentas` valida celular único y crea la cuenta en `PRIMARY` (`HTTP 201 Created`).
  2. `GET /api/cuentas/instancia` responde `HTTP 200 OK` reportando `instancia` y `nodoBaseDatos`.
