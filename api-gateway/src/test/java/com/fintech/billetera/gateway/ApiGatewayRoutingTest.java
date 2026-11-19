package com.fintech.billetera.gateway;

import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.cloud.gateway.route.Route;
import org.springframework.cloud.gateway.route.RouteLocator;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(properties = {
        "eureka.client.enabled=false",
        "spring.cloud.discovery.enabled=false"
})
class ApiGatewayRoutingTest {

    @Autowired
    private RouteLocator routeLocator;

    @Test
    void loadsDynamicLoadBalancedRoutesInExpectedOrder() {
        List<Route> routes = routeLocator.getRoutes().collectList().block();
        assertThat(routes).isNotNull().hasSize(4);

        assertThat(routes).extracting(Route::getId).containsExactly(
                "cuentas-db-estado",
                "cuentas-api",
                "transacciones-db-estado",
                "transacciones-api"
        );

        assertThat(routes).allSatisfy(route ->
                assertThat(route.getUri().getScheme()).isEqualTo("lb")
        );
    }
}
