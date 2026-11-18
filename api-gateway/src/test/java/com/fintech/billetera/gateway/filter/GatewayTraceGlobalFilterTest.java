package com.fintech.billetera.gateway.filter;

import org.junit.jupiter.api.Test;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import reactor.core.publisher.Mono;

import static org.assertj.core.api.Assertions.assertThat;

class GatewayTraceGlobalFilterTest {

    @Test
    void addsGatewayHandledHeaderBeforeCommitWithoutRemovingDownstreamHeaders() {
        GatewayTraceGlobalFilter filter = new GatewayTraceGlobalFilter();
        MockServerHttpRequest request = MockServerHttpRequest.get("/api/cuentas/0991112233")
                .header("X-Consistencia", "CRITICA")
                .build();
        MockServerWebExchange exchange = MockServerWebExchange.from(request);

        GatewayFilterChain chain = ex -> {
            ex.getResponse().getHeaders().add("X-Service-Instance", "ms-cuentas-1:8081");
            return ex.getResponse().setComplete();
        };

        filter.filter(exchange, chain).block();

        assertThat(exchange.getResponse().getHeaders().getFirst(GatewayTraceGlobalFilter.HEADER_GATEWAY_HANDLED))
                .isEqualTo(GatewayTraceGlobalFilter.VALUE_GATEWAY_HANDLED);
        assertThat(exchange.getResponse().getHeaders().getFirst("X-Service-Instance"))
                .isEqualTo("ms-cuentas-1:8081");
        assertThat(exchange.getRequest().getHeaders().getFirst("X-Consistencia"))
                .isEqualTo("CRITICA");
    }
}
