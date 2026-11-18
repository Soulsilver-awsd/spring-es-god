# 5.1 Contratos de Interfaz REST y Formato `ApiResponse<T>`

## 1. Envoltorio Estándar de Respuesta (`ApiResponse<T>`)

Toda operación de negocio retorna una estructura JSON uniforme junto con encabezados HTTP de trazabilidad (`X-Gateway-Handled`, `X-Service-Instance`, `X-Db-Node`, `X-Db-Fallback`):

```json
{
  "estado": "OK",
  "mensaje": "Transferencia realizada con éxito",
  "datos": {
    "comprobante": "TX-2026-0041",
    "origen": "0991112233",
    "destino": "0984445566",
    "monto": 25.00,
    "nuevoSaldoOrigen": 175.00
  },
  "auditoriaTecnica": {
    "servicioOrigen": "ms-transacciones:8083",
    "instanciaCuentasConsultada": "ms-cuentas-2 (172.18.0.5:8082)",
    "nodoBaseDatos": "postgres-primary (172.18.0.2:5432, recovery=false)",
    "politicaEnrutamiento": "ESCRITURA_DIRECTA"
  }
}
```

### Valores posibles de `politicaEnrutamiento`
- `ESCRITURA_DIRECTA`: Operaciones `POST`/`PUT`/`PATCH` dirigidas al Primario.
- `LECTURA_CRITICA_PRIMARIO`: Endpoints `/saldo-critico`, `/comprobante/{codigo}` o lectura con encabezado `X-Consistencia: CRITICA`.
- `ROUND_ROBIN_REPLICA`: Lecturas ordinarias repartidas entre `REPLICA_1` y `REPLICA_2`.
- `FAILOVER_REPLICA`: Lectura rescatada tras caída de una réplica (redirigida a réplica sana o Primario).

---

## 2. Endpoints de `ms-cuentas` (vía Gateway `http://localhost:8080`)

| Método | Ruta | Nodo BD | Entrada / Encabezados | Respuesta / Códigos |
|---|---|---|---|---|
| `GET` | `/api/cuentas/{celular}` | `REPLICA` (o `PRIMARY` si `X-Consistencia: CRITICA`) | Path `celular` (ej. `0991112233`) | `200 OK` (`CuentaDto`), `404 Not Found` |
| `GET` | `/api/cuentas/{celular}/contactos` | `REPLICA` | Path `celular` | `200 OK` (`List<ContactoDto>`), `404 Not Found` |
| `GET` | `/api/cuentas/{celular}/saldo-critico` | `PRIMARY` | Path `celular` | `200 OK` (`SaldoCriticoDto`), `404 Not Found` |
| `GET` | `/api/cuentas/instancia` | `REPLICA` | — | `200 OK` (diagnóstico para P02/P03) |
| `POST` | `/api/cuentas/movimiento-interno` | `PRIMARY` | JSON `{celularOrigen, celularDestino, monto}` | `200 OK` (`MovimientoInternoResponse`), `400`, `404`, `409` |
| `POST` | `/api/cuentas` | `PRIMARY` | JSON `{numeroCelular, titular, saldo, limiteDiario}` | `201 Created`, `400`, `409` |
| `GET` | `/api/cuentas/db/estado` | Memoria / Sondeo | — | `200 OK` (estado de réplicas y métricas) |

### Ejemplo de cuerpo `POST /api/cuentas/movimiento-interno`

```json
{
  "celularOrigen": "0991112233",
  "celularDestino": "0984445566",
  "monto": 25.00
}
```

---

## 3. Endpoints de `ms-transacciones` (vía Gateway `http://localhost:8080`)

| Método | Ruta | Nodo BD | Entrada / Encabezados | Respuesta / Códigos |
|---|---|---|---|---|
| `POST` | `/api/transacciones/transferir` | `PRIMARY` + `lb://ms-cuentas` | JSON `{celularOrigen, celularDestino, monto, motivo}` | `201 Created` (`ComprobanteDto`), `400`, `409`, `503` |
| `GET` | `/api/transacciones/historial/{celular}` | `REPLICA` | Path `celular` | `200 OK` (`List<TransaccionDto>`) |
| `GET` | `/api/transacciones/comprobante/{codigo}` | `PRIMARY` | Path `codigo` (ej. `TX-2026-0041`) | `200 OK` (`TransaccionDto`), `404 Not Found` |
| `GET` | `/api/transacciones/db/estado` | Memoria / Sondeo | — | `200 OK` (estado de réplicas y métricas) |

### Ejemplo de cuerpo `POST /api/transacciones/transferir`

```json
{
  "celularOrigen": "0991112233",
  "celularDestino": "0984445566",
  "monto": 25.00,
  "motivo": "Pago almuerzo compartido"
}
```
