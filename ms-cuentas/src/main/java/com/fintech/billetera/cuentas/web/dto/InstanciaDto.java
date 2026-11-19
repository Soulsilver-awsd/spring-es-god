package com.fintech.billetera.cuentas.web.dto;

import java.time.Instant;

/**
 * Diagnostico liviano de la instancia que atendio la peticion.
 */
public record InstanciaDto(
        String instancia,
        int puerto,
        Instant timestamp
) {
}
