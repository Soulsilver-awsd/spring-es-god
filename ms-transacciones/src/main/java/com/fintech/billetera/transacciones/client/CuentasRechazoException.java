package com.fintech.billetera.transacciones.client;

import org.springframework.http.HttpStatus;

/**
 * ms-cuentas rechazo el movimiento por una regla de negocio ({@code 400}, {@code 404} o {@code 409}).
 * Ningun saldo fue alterado.
 */
public class CuentasRechazoException extends RuntimeException {

    private final HttpStatus status;
    private final String instanciaCuentas;

    public CuentasRechazoException(HttpStatus status, String mensaje, String instanciaCuentas) {
        super(mensaje);
        this.status = status;
        this.instanciaCuentas = instanciaCuentas;
    }

    public HttpStatus getStatus() {
        return status;
    }

    /** Instancia de ms-cuentas que emitio el rechazo, o {@code null} si no se informo. */
    public String getInstanciaCuentas() {
        return instanciaCuentas;
    }
}
