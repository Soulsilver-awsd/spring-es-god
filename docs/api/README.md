# Diseño Formal de API REST (`curl` + OpenAPI 3.0.3)
## Sistema Distribuido de Billetera Digital y Transferencias P2P (*Fintech*)

**Punto único de entrada HTTP:** `http://localhost:8080` (`api-gateway`)  
**Tablero de descubrimiento:** `http://localhost:8761` (`eureka-server`)  
**Especificación OpenAPI:** [openapi.yaml](openapi.yaml)  
**Scripts ejecutables `curl` (`P01–P08`):** [Bash (`curl-p01-p08.sh`)](curl-p01-p08.sh) · [PowerShell (`curl-p01-p08.ps1`)](curl-p01-p08.ps1)  
**Documentación relacionada:** [SRS Contratos REST](../srs/05-interfaces-y-datos/01-contratos-api-rest.md) · [SDD `ms-cuentas`](../sdd/03-diseno-ms-cuentas.md) · [SDD `ms-transacciones`](../sdd/04-diseno-ms-transacciones.md) · [SAD `ADR-007`](../sad/06-adrs-decisiones-arquitectonicas.md)

---

## 1. Convenciones Globales de la API

### Cabeceras HTTP
| Cabecera | Dirección | Valores / Formato | Propósito |
|---|---|---|---|
| `Content-Type` | Request | `application/json` | Requerido en endpoints `POST`. |
| `X-Consistencia` | Request (Opcional) | `CRITICA` | Fuerza lectura ordinaria `GET` al nodo `PRIMARY` (*RYOW*). |
| `X-Gateway-Handled` | Response | `api-gateway` | Confirma paso por `api-gateway` (`RF-11`). |
| `X-Service-Instance` | Response | `ms-cuentas-1:8081`, etc. | Identifica la instancia exacta que atendió la petición (`P02`, `P03`). |
| `X-Db-Node` | Response | `PRIMARY` / `REPLICA_1` / `REPLICA_2` | Nodo PostgreSQL real reportado desde la conexión JDBC. |
| `X-Db-Fallback` | Response | `true` / `false` | Indica si ocurrió *failover* automático por caída de réplica (`P06`). |

### Matriz Unificada de Códigos HTTP y Respuesta de Error
Toda respuesta de negocio (éxito o error controlado) utiliza el envoltorio `ApiResponse<T>`:

```json
{
  "estado": "ERROR",
  "mensaje": "Saldo insuficiente",
  "datos": null,
  "auditoriaTecnica": {
    "servicioOrigen": "ms-transacciones:8083",
    "instanciaCuentasConsultada": "ms-cuentas-1:8081",
    "nodoBaseDatos": "PRIMARY (172.18.0.2:5432, recovery=false)",
    "politicaEnrutamiento": "ESCRITURA_DIRECTA"
  }
}
```

| Código HTTP | Significado en el Dominio | Casos Típicos |
|---|---|---|
| `200 OK` | Consulta o movimiento interno exitoso | `GET` de cuenta/contactos/saldo/historial/comprobante/estado, `POST /movimiento-interno` |
| `201 Created` | Recurso creado en `PRIMARY` | `POST /api/cuentas`, `POST /api/transacciones/transferir` |
| `400 Bad Request` | Error de validación de entrada | `monto <= 0`, campos en blanco, `celularOrigen == celularDestino` |
| `404 Not Found` | Recurso inexistente | Celular no registrado o `codigoComprobante` inexistente |
| `409 Conflict` | Violación de regla de negocio | Saldo insuficiente, límite diario excedido, cuenta `BLOQUEADA` o celular duplicado |
| `503 Service Unavailable` | Dependencia interna indisponible | Sin instancias `UP` de `ms-cuentas` en Eureka durante transferencia |

---

## 2. Endpoints de `ms-cuentas` (vía Gateway `:8080`)

### 2.1 `GET /api/cuentas/{celular}` — Consulta Ordinaria de Cuenta (`REPLICA` o `PRIMARY`)
- **Política:** `@UsarNodo(REPLICA)` en *Round-Robin*; si se envía `X-Consistencia: CRITICA`, enruta a `PRIMARY`.

```bash
# Lectura ordinaria (Replica 1 o Replica 2)
curl -i http://localhost:8080/api/cuentas/0991112233

# Lectura forzada al Primario
curl -i -H "X-Consistencia: CRITICA" http://localhost:8080/api/cuentas/0991112233
```

```json
{
  "estado": "OK",
  "mensaje": "Cuenta consultada correctamente",
  "datos": {
    "numeroCelular": "0991112233",
    "titular": "Ana Torres",
    "saldo": 500.00,
    "limiteDiario": 300.00,
    "consumidoHoy": 0.00,
    "estado": "ACTIVA"
  },
  "auditoriaTecnica": {
    "servicioOrigen": "ms-cuentas-1:8081",
    "instanciaCuentasConsultada": null,
    "nodoBaseDatos": "REPLICA_1 (172.18.0.3:5432, recovery=true)",
    "politicaEnrutamiento": "ROUND_ROBIN_REPLICA"
  }
}
```

---

### 2.2 `GET /api/cuentas/{celular}/contactos` — Contactos Frecuentes (`REPLICA`)

```bash
curl -i http://localhost:8080/api/cuentas/0991112233/contactos
```

```json
{
  "estado": "OK",
  "mensaje": "Contactos frecuentes obtenidos",
  "datos": [
    { "celularContacto": "0984445566", "alias": "Luis - Almuerzos" },
    { "celularContacto": "0977778899", "alias": "Carla - Oficina" }
  ],
  "auditoriaTecnica": {
    "servicioOrigen": "ms-cuentas-2:8082",
    "instanciaCuentasConsultada": null,
    "nodoBaseDatos": "REPLICA_2 (172.18.0.4:5432, recovery=true)",
    "politicaEnrutamiento": "ROUND_ROBIN_REPLICA"
  }
}
```

---

### 2.3 `GET /api/cuentas/{celular}/saldo-critico` — Saldo Inmediato *RYOW* (`PRIMARY`)

```bash
curl -i http://localhost:8080/api/cuentas/0991112233/saldo-critico
```

```json
{
  "estado": "OK",
  "mensaje": "Saldo critico verificado en nodo primario",
  "datos": {
    "numeroCelular": "0991112233",
    "saldo": 475.00,
    "limiteDiario": 300.00,
    "consumidoHoy": 25.00,
    "consultadoEn": "2026-11-18T18:05:10Z"
  },
  "auditoriaTecnica": {
    "servicioOrigen": "ms-cuentas-1:8081",
    "instanciaCuentasConsultada": null,
    "nodoBaseDatos": "PRIMARY (172.18.0.2:5432, recovery=false)",
    "politicaEnrutamiento": "LECTURA_CRITICA_PRIMARIO"
  }
}
```

---

### 2.4 `GET /api/cuentas/instancia` — Diagnóstico para Balanceo `P02` / `P03` (`REPLICA`)

```bash
curl -i http://localhost:8080/api/cuentas/instancia
```

```json
{
  "estado": "OK",
  "mensaje": "Instancia operativa",
  "datos": {
    "instancia": "ms-cuentas-2:8082",
    "puerto": 8082,
    "timestamp": "2026-11-18T18:05:20Z"
  },
  "auditoriaTecnica": {
    "servicioOrigen": "ms-cuentas-2:8082",
    "instanciaCuentasConsultada": null,
    "nodoBaseDatos": "REPLICA_1 (172.18.0.3:5432, recovery=true)",
    "politicaEnrutamiento": "ROUND_ROBIN_REPLICA"
  }
}
```

---

### 2.5 `POST /api/cuentas` — Alta de Cuenta (`PRIMARY`)

```bash
curl -i -X POST http://localhost:8080/api/cuentas \
  -H "Content-Type: application/json" \
  -d '{"numeroCelular":"0951234567","titular":"Mario Ruiz","saldo":250.00,"limiteDiario":150.00}'
```

Respuesta `201 Created`:
```json
{
  "estado": "OK",
  "mensaje": "Cuenta creada exitosamente",
  "datos": {
    "numeroCelular": "0951234567",
    "titular": "Mario Ruiz",
    "saldo": 250.00,
    "limiteDiario": 150.00,
    "consumidoHoy": 0.00,
    "estado": "ACTIVA"
  },
  "auditoriaTecnica": {
    "servicioOrigen": "ms-cuentas-1:8081",
    "instanciaCuentasConsultada": null,
    "nodoBaseDatos": "PRIMARY (172.18.0.2:5432, recovery=false)",
    "politicaEnrutamiento": "ESCRITURA_DIRECTA"
  }
}
```

---

### 2.6 `POST /api/cuentas/movimiento-interno` — Débito/Crédito Atómico (`PRIMARY`)
Endpoint consumido internamente por `ms-transacciones` vía `http://ms-cuentas/api/cuentas/movimiento-interno` (también accesible para pruebas directas).

```bash
curl -i -X POST http://localhost:8080/api/cuentas/movimiento-interno \
  -H "Content-Type: application/json" \
  -d '{"celularOrigen":"0991112233","celularDestino":"0984445566","monto":25.00}'
```

Respuesta `200 OK`:
```json
{
  "estado": "OK",
  "mensaje": "Movimiento interno aplicado",
  "datos": {
    "celularOrigen": "0991112233",
    "celularDestino": "0984445566",
    "monto": 25.00,
    "nuevoSaldoOrigen": 475.00,
    "nuevoSaldoDestino": 175.00,
    "instanciaAtendio": "ms-cuentas-2:8082"
  },
  "auditoriaTecnica": {
    "servicioOrigen": "ms-cuentas-2:8082",
    "instanciaCuentasConsultada": null,
    "nodoBaseDatos": "PRIMARY (172.18.0.2:5432, recovery=false)",
    "politicaEnrutamiento": "ESCRITURA_DIRECTA"
  }
}
```

---

### 2.7 `GET /api/cuentas/db/estado` — Estado de Réplicas y Contadores (`ms-cuentas`)

```bash
curl -s http://localhost:8080/api/cuentas/db/estado
```

*(Estructura JSON detallada en [Diseño `common-persistence`](../sdd/02-diseno-common-persistence.md#6-endpoint-de-diagn%C3%B3stico-apidbestado).)*

---

## 3. Endpoints de `ms-transacciones` (vía Gateway `:8080`)

### 3.1 `POST /api/transacciones/transferir` — Transferencia P2P (`PRIMARY` + `lb://ms-cuentas`)

```bash
curl -i -X POST http://localhost:8080/api/transacciones/transferir \
  -H "Content-Type: application/json" \
  -d '{"celularOrigen":"0991112233","celularDestino":"0984445566","monto":25.00,"motivo":"Pago almuerzo compartido"}'
```

Respuesta `201 Created`:
```json
{
  "estado": "OK",
  "mensaje": "Transferencia realizada con exito",
  "datos": {
    "codigoComprobante": "TX-2026-0001",
    "celularOrigen": "0991112233",
    "celularDestino": "0984445566",
    "monto": 25.00,
    "motivo": "Pago almuerzo compartido",
    "estado": "EXITOSA",
    "nuevoSaldoOrigen": 475.00,
    "fechaHora": "2026-11-18T18:05:08Z"
  },
  "auditoriaTecnica": {
    "servicioOrigen": "ms-transacciones:8083",
    "instanciaCuentasConsultada": "ms-cuentas-2:8082",
    "nodoBaseDatos": "PRIMARY (172.18.0.2:5432, recovery=false)",
    "politicaEnrutamiento": "ESCRITURA_DIRECTA"
  }
}
```

---

### 3.2 `GET /api/transacciones/historial/{celular}` — Historial de Movimientos (`REPLICA`)

```bash
curl -i http://localhost:8080/api/transacciones/historial/0991112233
```

```json
{
  "estado": "OK",
  "mensaje": "Historial obtenido",
  "datos": [
    {
      "codigoComprobante": "TX-2026-0001",
      "celularOrigen": "0991112233",
      "celularDestino": "0984445566",
      "monto": 25.00,
      "motivo": "Pago almuerzo compartido",
      "estado": "EXITOSA",
      "fechaHora": "2026-11-18T18:05:08Z"
    }
  ],
  "auditoriaTecnica": {
    "servicioOrigen": "ms-transacciones:8083",
    "instanciaCuentasConsultada": null,
    "nodoBaseDatos": "REPLICA_2 (172.18.0.4:5432, recovery=true)",
    "politicaEnrutamiento": "ROUND_ROBIN_REPLICA"
  }
}
```

---

### 3.3 `GET /api/transacciones/comprobante/{codigo}` — Comprobante Crítico *RYOW* (`PRIMARY`)

```bash
curl -i http://localhost:8080/api/transacciones/comprobante/TX-2026-0001
```

```json
{
  "estado": "OK",
  "mensaje": "Comprobante verificado en nodo primario",
  "datos": {
    "codigoComprobante": "TX-2026-0001",
    "celularOrigen": "0991112233",
    "celularDestino": "0984445566",
    "monto": 25.00,
    "motivo": "Pago almuerzo compartido",
    "estado": "EXITOSA",
    "fechaHora": "2026-11-18T18:05:08Z"
  },
  "auditoriaTecnica": {
    "servicioOrigen": "ms-transacciones:8083",
    "instanciaCuentasConsultada": null,
    "nodoBaseDatos": "PRIMARY (172.18.0.2:5432, recovery=false)",
    "politicaEnrutamiento": "LECTURA_CRITICA_PRIMARIO"
  }
}
```

---

### 3.4 `GET /api/transacciones/db/estado` — Estado de Réplicas (`ms-transacciones`)

```bash
curl -s http://localhost:8080/api/transacciones/db/estado
```
