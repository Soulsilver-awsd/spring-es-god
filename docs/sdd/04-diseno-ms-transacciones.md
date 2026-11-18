# 4. Diseño Detallado de `ms-transacciones`

**Documentos relacionados:** [Índice del SDD](README.md) · [Requisitos `RF-06`–`RF-08`](../srs/03-requisitos-funcionales/02-rf-transacciones-p2p.md) · [Diseño `ms-cuentas`](03-diseno-ms-cuentas.md) · [Contratos REST](../srs/05-interfaces-y-datos/01-contratos-api-rest.md)

---

## 1. Diseño del Modelo de Dominio (JPA sobre `tx_db`)

### Entidad `Transaccion` (`tx_db.transacciones`)
| Atributo Java | Columna SQL | Tipo Java / SQL | Restricciones |
|---|---|---|---|
| `id` | `id` | `Long` / `BIGSERIAL` | `@Id`, `@GeneratedValue(IDENTITY)` |
| `codigoComprobante` | `codigo_comprobante` | `String` / `VARCHAR(40)` | `nullable = false`, `unique = true` |
| `celularOrigen` | `celular_origen` | `String` / `VARCHAR(20)` | `nullable = false` (referencia lógica sin FK) |
| `celularDestino` | `celular_destino` | `String` / `VARCHAR(20)` | `nullable = false` (referencia lógica sin FK) |
| `monto` | `monto` | `BigDecimal` / `NUMERIC(14,2)` | `nullable = false`, `> 0` |
| `motivo` | `motivo` | `String` / `VARCHAR(160)` | `nullable = false` |
| `estado` | `estado` | `EstadoTransaccion` / `VARCHAR(20)` | `EXITOSA` \| `RECHAZADA` |
| `fechaHora` | `fecha_hora` | `OffsetDateTime` / `TIMESTAMPTZ` | `nullable = false` |

### `TransaccionRepository`
- `List<Transaccion> findByCelularOrigenOrCelularDestinoOrderByFechaHoraDesc(String origen, String destino);`
- `Optional<Transaccion> findByCodigoComprobante(String codigoComprobante);`

---

## 2. Cliente HTTP Dinámico `CuentasHttpClient`

### Configuración (`RestClientConfig`)
```java
@Bean
@LoadBalanced
public RestClient.Builder loadBalancedRestClientBuilder() {
    SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
    factory.setConnectTimeout(Duration.ofSeconds(3));
    factory.setReadTimeout(Duration.ofSeconds(5));
    return RestClient.builder().requestFactory(factory);
}
```

### Llamada a `lb://ms-cuentas`
- URL lógica obligatoria: `http://ms-cuentas/api/cuentas/movimiento-interno` (prohibido usar IP o puerto fijo).
- Al recibir la respuesta de `ms-cuentas`, `CuentasHttpClient` extrae:
  1. El cuerpo `ApiResponse<MovimientoInternoResponse>`.
  2. La cabecera `X-Service-Instance` (o `auditoriaTecnica.servicioOrigen`) para poblar `instanciaCuentasConsultada` en la auditoría final de `ms-transacciones`.

### Mapeo de errores HTTP inter-servicios
| Condición en `CuentasHttpClient` | Excepción Propagada | Código HTTP de `ms-transacciones` |
|---|---|---|
| `ms-cuentas` responde `400 Bad Request` | `BusinessValidationException` | `400 Bad Request` |
| `ms-cuentas` responde `404 Not Found` | `ResourceNotFoundException` | `404 Not Found` |
| `ms-cuentas` responde `409 Conflict` (saldo/límite/bloqueo) | `BusinessConflictException` | `409 Conflict` |
| No hay instancias en Eureka o `ResourceAccessException` / `5xx` | `ServiceUnavailableException` | `503 Service Unavailable` |

---

## 3. Algoritmo Detallado de `TransferenciaOrchestratorService`

```text
ENTRADA: TransferenciaRequest(celularOrigen, celularDestino, monto, motivo)
@UsarNodo(value = TipoNodo.PRIMARY, escritura = true)
1. Validar request con Jakarta Validation (@NotBlank celulares y motivo, @DecimalMin("0.01") monto).
2. Validar celularOrigen != celularDestino -> sino 400 Bad Request.
3. Generar codigoComprobante unico: "TX-" + Year.now() + "-" + UUID/Secuencia corta (ej. "TX-2026-0041").
4. Invocar cuentasHttpClient.ejecutarMovimiento(celularOrigen, celularDestino, monto):
   a. SI falla por regla de negocio (400 / 404 / 409):
      - Persistir registro de auditoria en tx_db.transacciones con estado = RECHAZADA
        (en transaccion independiente REQUIRES_NEW si se desea conservar traza del intento fallido)
        sin modificar ningun saldo en cuentas_db.
      - Lanzar la excepcion de negocio correspondiente con el mensaje recibido de ms-cuentas.
   b. SI falla por indisponibilidad (503 / sin instancias):
      - Retornar HTTP 503 Service Unavailable ("Servicio ms-cuentas no disponible temporalmente").
5. SI ms-cuentas responde 200 OK:
   a. Construir Transaccion(codigoComprobante, celularOrigen, celularDestino, monto, motivo, EXITOSA, OffsetDateTime.now()).
   b. Guardar en tx_db.transacciones (PRIMARY).
   c. Capturar DbAuditor.capturarAuditoriaActual() y adjuntar instanciaCuentasConsultada.
   d. Retornar ComprobanteDto con HTTP 201 Created.
```

> **Nota sobre transaccionalidad:** El guardado del registro `RECHAZADA` (cuando `ms-cuentas` rechaza por saldo o límite) no debe envolverse junto con excepciones que hagan *rollback* automático sobre `tx_db`; si se registra el rechazo, se guarda explícitamente antes de lanzar la excepción controlada o mediante un método auxiliar separado con `@UsarNodo(PRIMARY, escritura = true)`.

---

## 4. Diseño de Consultas (`TransaccionConsultaService`)

| Método | Anotación `@UsarNodo` | Endpoint | Contrato de Salida |
|---|---|---|---|
| `listarHistorial(celular)` | `@UsarNodo(TipoNodo.REPLICA)` | `GET /api/transacciones/historial/{celular}` | `200 OK` con `List<TransaccionDto>` ordenada descendente por `fechaHora` (lista vacía `[]` si no registra movimientos). |
| `consultarComprobanteCritico(codigo)` | `@UsarNodo(TipoNodo.PRIMARY)` | `GET /api/transacciones/comprobante/{codigo}` | `200 OK` con `TransaccionDto` directo desde `PRIMARY`, o `404 Not Found` si no existe. |
