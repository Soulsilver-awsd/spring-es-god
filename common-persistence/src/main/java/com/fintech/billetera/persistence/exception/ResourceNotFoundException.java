package com.fintech.billetera.persistence.exception;

/**
 * Recurso de negocio inexistente (HTTP 404 Not Found).
 */
public class ResourceNotFoundException extends RuntimeException {

    public ResourceNotFoundException(String message) {
        super(message);
    }
}
