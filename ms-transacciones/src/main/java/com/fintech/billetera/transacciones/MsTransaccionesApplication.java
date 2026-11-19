package com.fintech.billetera.transacciones;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

/**
 * Microservicio orquestador de transferencias P2P y libro mayor ({@code tx_db}) en {@code :8083}.
 */
@SpringBootApplication
@ConfigurationPropertiesScan
public class MsTransaccionesApplication {

    public static void main(String[] args) {
        SpringApplication.run(MsTransaccionesApplication.class, args);
    }
}
