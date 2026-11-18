package com.fintech.billetera.transacciones.service;

import org.springframework.http.HttpStatus;

import com.fintech.billetera.persistence.audit.AuditoriaTecnicaDto;

/**
 * Error de negocio controlado que conserva la auditoria real del nodo que lo atendio (y, en
 * transferencias, la instancia de ms-cuentas que rechazo el movimiento).
 */
public class OperacionRechazadaException extends RuntimeException {

    private final HttpStatus status;
    private final AuditoriaTecnicaDto auditoria;

    public OperacionRechazadaException(HttpStatus status, String mensaje, AuditoriaTecnicaDto auditoria) {
        super(mensaje);
        this.status = status;
        this.auditoria = auditoria;
    }

    public HttpStatus getStatus() {
        return status;
    }

    public AuditoriaTecnicaDto getAuditoria() {
        return auditoria;
    }
}
