package com.fintech.billetera.cuentas.web.dto;

import com.fintech.billetera.cuentas.domain.EstadoCuenta;
import java.math.BigDecimal;

/**
 * Datos publicos de una cuenta consultada.
 */
public record CuentaDto(
        String numeroCelular,
        String titular,
        BigDecimal saldo,
        BigDecimal limiteDiario,
        BigDecimal consumidoHoy,
        EstadoCuenta estado
) {
}
