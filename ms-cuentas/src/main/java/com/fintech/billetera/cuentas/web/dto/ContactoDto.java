package com.fintech.billetera.cuentas.web.dto;

/**
 * Contacto frecuente expuesto al cliente.
 */
public record ContactoDto(
        String celularContacto,
        String alias
) {
}
