package com.fintech.billetera.persistence.exception;

/**
 * Conflicto por regla de negocio financiera (HTTP 409 Conflict).
 */
public class BusinessConflictException extends RuntimeException {

    public BusinessConflictException(String message) {
        super(message);
    }
}
