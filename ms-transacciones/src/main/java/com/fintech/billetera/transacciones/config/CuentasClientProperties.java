package com.fintech.billetera.transacciones.config;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Configuracion del cliente HTTP hacia ms-cuentas ({@code app.cuentas.*}).
 *
 * @param baseUrl        URL logica resuelta por LoadBalancer (siempre {@code http://ms-cuentas})
 * @param connectTimeout timeout de conexion (3 s)
 * @param readTimeout    timeout de lectura (5 s)
 */
@ConfigurationProperties(prefix = "app.cuentas")
public record CuentasClientProperties(
        @DefaultValue("http://ms-cuentas") String baseUrl,
        @DefaultValue("3s") Duration connectTimeout,
        @DefaultValue("5s") Duration readTimeout
) {
}
