package com.fintech.billetera.cuentas.web.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;

/**
 * Movimiento interno atomico entre dos billeteras.
 */
public record MovimientoInternoRequest(
        @NotBlank
        @Size(max = 20)
        String celularOrigen,

        @NotBlank
        @Size(max = 20)
        String celularDestino,

        @NotNull
        @DecimalMin(value = "0.01")
        @Digits(integer = 12, fraction = 2)
        BigDecimal monto
) {
}
