package com.fintech.billetera.gateway.filter;

import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

/**
 * Filtro global que agrega la cabecera de trazabilidad X-Gateway-Handled en cada respuesta
 * sin alterar cabeceras entrantes (X-Consistencia) ni de los microservicios (X-Service-Instance, X-Db-*).
 */
@Component
public class GatewayTraceGlobalFilter implements GlobalFilter, Ordered {

    public static final String HEADER_GATEWAY_HANDLED = "X-Gateway-Handled";
    public static final String VALUE_GATEWAY_HANDLED = "api-gateway";

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        exchange.getResponse().beforeCommit(() -> {
            exchange.getResponse().getHeaders().set(HEADER_GATEWAY_HANDLED, VALUE_GATEWAY_HANDLED);
            return Mono.empty();
        });
        return chain.filter(exchange);
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }
}
