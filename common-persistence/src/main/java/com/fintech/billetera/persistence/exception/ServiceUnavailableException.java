package com.fintech.billetera.persistence.exception;

/**
 * Microservicio dependiente no disponible en Eureka (HTTP 503 Service Unavailable).
 */
public class ServiceUnavailableException extends RuntimeException {

    public ServiceUnavailableException(String message) {
        super(message);
    }

    public ServiceUnavailableException(String message, Throwable cause) {
        super(message, cause);
    }
}
