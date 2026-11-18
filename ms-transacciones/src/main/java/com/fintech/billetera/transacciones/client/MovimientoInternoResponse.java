package com.fintech.billetera.transacciones.client;

import java.math.BigDecimal;

/**
 * {@code datos} de la respuesta de ms-cuentas al aplicar un movimiento interno.
 */
public record MovimientoInternoResponse(
        String celularOrigen,
        String celularDestino,
        BigDecimal monto,
        BigDecimal nuevoSaldoOrigen,
        BigDecimal nuevoSaldoDestino,
        String instanciaAtendio
) {
}
