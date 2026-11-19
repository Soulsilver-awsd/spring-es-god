package com.fintech.billetera.transacciones.client;

import java.math.BigDecimal;

/**
 * Cuerpo de {@code POST http://ms-cuentas/api/cuentas/movimiento-interno}.
 */
public record MovimientoInternoRequest(String celularOrigen, String celularDestino, BigDecimal monto) {
}
