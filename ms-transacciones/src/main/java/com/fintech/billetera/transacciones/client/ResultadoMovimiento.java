package com.fintech.billetera.transacciones.client;

/**
 * Movimiento aplicado por ms-cuentas junto con la instancia real que lo atendio.
 *
 * @param movimiento          datos devueltos por ms-cuentas
 * @param instanciaAtendio    instancia de ms-cuentas (ej. {@code ms-cuentas-2:8082}); puede ser {@code null}
 */
public record ResultadoMovimiento(MovimientoInternoResponse movimiento, String instanciaAtendio) {
}
