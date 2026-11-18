package com.fintech.billetera.transacciones.domain;

/**
 * Resultado de una transferencia registrada en el libro mayor.
 */
public enum EstadoTransaccion {
    /** ms-cuentas aplico el debito/credito. */
    EXITOSA,
    /** ms-cuentas rechazo el movimiento por regla de negocio; ningun saldo cambio. */
    RECHAZADA
}
