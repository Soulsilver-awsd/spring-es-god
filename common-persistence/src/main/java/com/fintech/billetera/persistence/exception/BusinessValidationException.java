package com.fintech.billetera.persistence.exception;

/**
 * Error de validacion de entrada (HTTP 400 Bad Request).
 */
public class BusinessValidationException extends RuntimeException {

    public BusinessValidationException(String message) {
        super(message);
    }
}
