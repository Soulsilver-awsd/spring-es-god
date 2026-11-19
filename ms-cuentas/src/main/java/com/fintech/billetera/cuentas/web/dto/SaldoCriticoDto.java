package com.fintech.billetera.cuentas.web.dto;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Saldo leido de forma critica desde el nodo primario (RYOW).
 */
public record SaldoCriticoDto(
        String numeroCelular,
        BigDecimal saldo,
        BigDecimal limiteDiario,
        BigDecimal consumidoHoy,
        Instant consultadoEn
) {
}
