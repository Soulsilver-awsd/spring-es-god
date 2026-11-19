package com.fintech.billetera.cuentas.web.dto;

import java.math.BigDecimal;

/**
 * Resultado de un movimiento interno aplicado en el nodo primario.
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
