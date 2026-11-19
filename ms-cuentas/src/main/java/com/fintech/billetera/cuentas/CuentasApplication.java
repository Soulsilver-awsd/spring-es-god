package com.fintech.billetera.cuentas;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Punto de entrada del microservicio de cuentas y saldos.
 */
@SpringBootApplication
public class CuentasApplication {

    public static void main(String[] args) {
        SpringApplication.run(CuentasApplication.class, args);
    }
}
