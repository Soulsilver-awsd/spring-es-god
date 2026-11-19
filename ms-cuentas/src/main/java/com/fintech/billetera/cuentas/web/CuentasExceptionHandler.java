package com.fintech.billetera.cuentas.web;

import com.fintech.billetera.persistence.audit.ApiResponse;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Manejo especifico de errores de integridad de cuentas.
 * Los errores de negocio (400/404/409/503) ya los cubre BaseErrorHandler.
 */
@RestControllerAdvice
public class CuentasExceptionHandler {

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ApiResponse<Void>> handleDataIntegrity(DataIntegrityViolationException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ApiResponse.error("El numero de celular ya esta registrado", null));
    }
}
