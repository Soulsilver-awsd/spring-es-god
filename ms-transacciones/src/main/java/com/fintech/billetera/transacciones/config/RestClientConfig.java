package com.fintech.billetera.transacciones.config;

import java.time.Clock;

import org.springframework.boot.autoconfigure.web.client.RestClientBuilderConfigurer;
import org.springframework.cloud.client.loadbalancer.LoadBalanced;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * Cliente HTTP {@code @LoadBalanced}: resuelve {@code http://ms-cuentas} contra el registro de
 * Eureka mediante Spring Cloud LoadBalancer (ADR-003, ADR-006).
 */
@Configuration(proxyBeanMethods = false)
public class RestClientConfig {

    @Bean
    @LoadBalanced
    public RestClient.Builder loadBalancedRestClientBuilder(RestClientBuilderConfigurer configurer,
                                                            CuentasClientProperties properties) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(properties.connectTimeout());
        factory.setReadTimeout(properties.readTimeout());
        // El configurer aplica los convertidores JSON de Spring Boot; luego fijamos los timeouts.
        return configurer.configure(RestClient.builder()).requestFactory(factory);
    }

    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }
}
