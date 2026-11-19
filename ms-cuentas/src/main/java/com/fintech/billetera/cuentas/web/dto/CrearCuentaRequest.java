package com.fintech.billetera.cuentas.web.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;

/**
 * Alta de una nueva billetera.
 */
public record CrearCuentaRequest(
        @NotBlank
        @Size(max = 20)
        String numeroCelular,

        @NotBlank
        @Size(max = 120)
        String titular,

        @NotNull
        @DecimalMin(value = "0.00")
        @Digits(integer = 12, fraction = 2)
        BigDecimal saldo,

        @NotNull
        @DecimalMin(value = "0.01")
        @Digits(integer = 12, fraction = 2)
        BigDecimal limiteDiario
) {
}
