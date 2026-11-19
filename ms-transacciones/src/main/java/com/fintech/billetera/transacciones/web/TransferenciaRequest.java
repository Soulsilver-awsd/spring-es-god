package com.fintech.billetera.transacciones.web;

import java.math.BigDecimal;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Cuerpo de {@code POST /api/transacciones/transferir}.
 */
public record TransferenciaRequest(
        @NotBlank @Size(max = 20) String celularOrigen,
        @NotBlank @Size(max = 20) String celularDestino,
        @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor o igual a 0.01")
        @Digits(integer = 12, fraction = 2, message = "admite como maximo 2 decimales") BigDecimal monto,
        @NotBlank @Size(max = 160) String motivo
) {
}
