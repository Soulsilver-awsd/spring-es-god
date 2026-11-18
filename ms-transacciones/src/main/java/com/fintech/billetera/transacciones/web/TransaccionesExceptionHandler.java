package com.fintech.billetera.transacciones.web;

import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.fintech.billetera.persistence.audit.ApiResponse;
import com.fintech.billetera.transacciones.service.OperacionRechazadaException;

/**
 * Traduce los rechazos de negocio conservando la auditoria real capturada en el servicio.
 * Los errores comunes (validacion 400, 503, etc.) los resuelve {@code BaseErrorHandler} de
 * common-persistence; por eso este advice no declara un manejador generico de {@code Exception}
 * (al tener mayor precedencia, lo interceptaria todo).
 */
@RestControllerAdvice
@Order(Ordered.HIGHEST_PRECEDENCE)
public class TransaccionesExceptionHandler {

    @ExceptionHandler(OperacionRechazadaException.class)
    public ResponseEntity<ApiResponse<Void>> handleRechazo(OperacionRechazadaException ex) {
        return ResponseEntity.status(ex.getStatus()).body(ApiResponse.error(ex.getMessage(), ex.getAuditoria()));
    }
}
