package com.fintech.billetera.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Puerta de enlace HTTP unica (:8080) con enrutamiento dinamico lb:// via Eureka y LoadBalancer.
 */
@SpringBootApplication
public class ApiGatewayApplication {

    public static void main(String[] args) {
        SpringApplication.run(ApiGatewayApplication.class, args);
    }
}
