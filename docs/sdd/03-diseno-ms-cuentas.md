# 3. Diseño Detallado de `ms-cuentas`

**Documentos relacionados:** [Índice del SDD](README.md) · [Requisitos `RF-01`–`RF-05`](../srs/03-requisitos-funcionales/01-rf-cuentas-saldos.md) · [Contratos REST](../srs/05-interfaces-y-datos/01-contratos-api-rest.md) · [Modelo de Datos](../srs/05-interfaces-y-datos/02-modelo-datos-esquemas.md)

---

## 1. Diseño del Modelo de Dominio (JPA sobre `cuentas_db`)

### Entidad `Cuenta` (`cuentas_db.cuentas`)
| Atributo Java | Columna SQL | Tipo Java / SQL | Restricciones |
|---|---|---|---|
| `id` | `id` | `Long` / `BIGSERIAL` | `@Id`, `@GeneratedValue(IDENTITY)` |
| `numeroCelular` | `numero_celular` | `String` / `VARCHAR(20)` | `nullable = false`, `unique = true` |
| `titular` | `titular` | `String` / `VARCHAR(120)` | `nullable = false` |
| `saldo` | `saldo` | `BigDecimal` / `NUMERIC(14,2)` | `nullable = false`, `>= 0` |
| `limiteDiario` | `limite_diario` | `BigDecimal` / `NUMERIC(14,2)` | `nullable = false`, `> 0` |
| `consumidoHoy` | `consumido_hoy` | `BigDecimal` / `NUMERIC(14,2)` | `nullable = false`, default `0.00` |
| `estado` | `estado` | `EstadoCuenta` / `VARCHAR(20)` | `ACTIVA` \| `BLOQUEADA` |

### Entidad `ContactoFrecuente` (`cuentas_db.contactos_frecuentes`)
| Atributo Java | Columna SQL | Tipo Java / SQL | Restricciones |
|---|---|---|---|
| `id` | `id` | `Long` / `BIGSERIAL` | `@Id`, `@GeneratedValue(IDENTITY)` |
| `cuentaPropietario` | `cuenta_propietario_id` | `Cuenta` / `BIGINT` | `@ManyToOne(fetch = LAZY)` |
| `celularContacto` | `celular_contacto` | `String` / `VARCHAR(20)` | `nullable = false` |
| `alias` | `alias` | `String` / `VARCHAR(80)` | `nullable = false` |

---

## 2. Repositorios Spring Data JPA

### `CuentaRepository`
- `Optional<Cuenta> findByNumeroCelular(String numeroCelular);` (lecturas ordinarias y críticas).
- `boolean existsByNumeroCelular(String numeroCelular);`
- Bloqueo pesimista para movimientos concurrentes:
  ```java
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query("SELECT c FROM Cuenta c WHERE c.numeroCelular = :celular")
  Optional<Cuenta> findByNumeroCelularForUpdate(@Param("celular") String celular);
  ```

### `ContactoFrecuenteRepository`
- `List<ContactoFrecuente> findByCuentaPropietarioNumeroCelularOrderByAliasAsc(String celular);`

---

## 3. Diseño de Servicios y Política `@UsarNodo`

| Servicio / Método | Anotación `@UsarNodo` | Transaccionalidad | Comportamiento |
|---|---|---|---|
| `CuentaConsultaService.obtenerPorCelular(celular)` | `@UsarNodo(TipoNodo.REPLICA)` | `@Transactional(readOnly = true)` | Consulta perfil y saldo visible (si llega `X-Consistencia: CRITICA`, el AOP redirige a `PRIMARY`). |
| `CuentaConsultaService.obtenerContactos(celular)` | `@UsarNodo(TipoNodo.REPLICA)` | `@Transactional(readOnly = true)` | Verifica existencia de cuenta y retorna sus contactos frecuentes. |
| `CuentaConsultaService.obtenerSaldoCritico(celular)` | `@UsarNodo(TipoNodo.PRIMARY)` | `@Transactional(readOnly = true)` | Lectura obligatoria en `PRIMARY` (*RYOW*). |
| `CuentaConsultaService.obtenerDiagnosticoInstancia()` | `@UsarNodo(TipoNodo.REPLICA)` | `@Transactional(readOnly = true)` | Ejecuta lectura liviana (`SELECT 1` / auditoría) para `P02` y `P03`. |
| `MovimientoCuentaService.crearCuenta(req)` | `@UsarNodo(value = TipoNodo.PRIMARY, escritura = true)` | `@Transactional` | Valida unicidad de celular y persiste cuenta inicial en `PRIMARY`. |
| `MovimientoCuentaService.ejecutarMovimientoInterno(req)` | `@UsarNodo(value = TipoNodo.PRIMARY, escritura = true)` | `@Transactional` | Débito/crédito atómico ACID entre cuentas. |

---

## 4. Algoritmo Detallado de `MovimientoCuentaService.ejecutarMovimientoInterno`

```text
ENTRADA: MovimientoInternoRequest(celularOrigen, celularDestino, monto)
1. Validar que monto != null y monto.compareTo(BigDecimal.ZERO) > 0 -> sino 400 Bad Request.
2. Validar que !celularOrigen.equals(celularDestino) -> sino 400 Bad Request ("Cuenta origen y destino deben ser distintas").
3. Ordenamiento deterministico anti-deadlock:
   primero = (celularOrigen.compareTo(celularDestino) < 0) ? celularOrigen : celularDestino
   segundo = primero.equals(celularOrigen) ? celularDestino : celularOrigen
4. Bloquear en orden fijo:
   c1 = cuentaRepository.findByNumeroCelularForUpdate(primero)
   c2 = cuentaRepository.findByNumeroCelularForUpdate(segundo)
   (Asignar origen y destino desde c1/c2; si alguna no existe -> 404 Not Found).
5. Validar estado de ambas cuentas == EstadoCuenta.ACTIVA:
   Si origen o destino esta BLOQUEADA -> 409 Conflict ("Cuenta bloqueada para transferencias").
6. Validar fondos en origen:
   Si origen.getSaldo().compareTo(monto) < 0 -> 409 Conflict ("Saldo insuficiente").
7. Validar cupo diario en origen:
   nuevoConsumido = origen.getConsumidoHoy().add(monto)
   Si nuevoConsumido.compareTo(origen.getLimiteDiario()) > 0 -> 409 Conflict ("Limite diario excedido").
8. Aplicar actualizacion en memoria (flush al commit):
   origen.setSaldo(origen.getSaldo().subtract(monto))
   origen.setConsumidoHoy(nuevoConsumido)
   destino.setSaldo(destino.getSaldo().add(monto))
9. Capturar DbAuditor.capturarAuditoriaActual() y retornar MovimientoInternoResponse:
   { celularOrigen, celularDestino, monto, nuevoSaldoOrigen, nuevoSaldoDestino, instanciaAtendio }
```

---

## 5. Contratos DTO y Códigos de Respuesta HTTP en `CuentaController`

| Endpoint | DTO Entrada | DTO `datos` Salida | Errores Controlados |
|---|---|---|---|
| `GET /api/cuentas/{celular}` | Path `celular` | `CuentaDto(numeroCelular, titular, saldo, limiteDiario, consumidoHoy, estado)` | `404 Not Found` |
| `GET /api/cuentas/{celular}/contactos` | Path `celular` | `List<ContactoDto(celularContacto, alias)>` | `404 Not Found` |
| `GET /api/cuentas/{celular}/saldo-critico` | Path `celular` | `SaldoCriticoDto(numeroCelular, saldo, limiteDiario, consumidoHoy, consultadoEn)` | `404 Not Found` |
| `GET /api/cuentas/instancia` | — | `InstanciaDto(instancia, puerto, timestamp)` | — |
| `POST /api/cuentas` | `CrearCuentaRequest` | `CuentaDto` (`201 Created`) | `400`, `409` (celular duplicado) |
| `POST /api/cuentas/movimiento-interno` | `MovimientoInternoRequest` | `MovimientoInternoResponse` (`200 OK`) | `400`, `404`, `409` |
