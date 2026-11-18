# 5. Diseño Detallado de `eureka-server` y `api-gateway`

**Documentos relacionados:** [Índice del SDD](README.md) · [Requisitos `RF-10`–`RF-11`](../srs/03-requisitos-funcionales/03-rf-gateway-descubrimiento.md) · [Disponibilidad `RNF-01`–`RNF-02`](../srs/04-requisitos-no-funcionales/01-rnf-disponibilidad-fallos.md)

---

## 1. Diseño de `eureka-server` (`:8761`)

### Propósito y Configuración Exacta (`application.yml`)
`eureka-server` actúa como servidor autónomo de registro sin replicarse contra pares (*standalone*):

```yaml
server:
  port: 8761

spring:
  application:
    name: eureka-server

eureka:
  client:
    register-with-eureka: false
    fetch-registry: false
  server:
    enable-self-preservation: false
    eviction-interval-timer-in-ms: 3000
```

- **`enable-self-preservation: false` y `eviction-interval-timer-in-ms: 3000`**: indispensables en laboratorio para que al simular la caída abrupta de `ms-cuentas-2` (`P03`), Eureka expulse el *lease* expirado en pocos segundos en lugar de retener la instancia caída en modo de autopreservación.

---

## 2. Configuración de Clientes Eureka (Microservicios y Gateway)

Todos los clientes (`ms-cuentas-1`, `ms-cuentas-2`, `ms-transacciones`, `api-gateway`) configuran renovación rápida y expiración corta:

```yaml
eureka:
  client:
    service-url:
      defaultZone: ${EUREKA_URI:http://eureka-server:8761/eureka/}
    registry-fetch-interval-seconds: 5
  instance:
    prefer-ip-address: true
    instance-id: ${spring.application.name}:${INSTANCE_ID:${random.value}}:${server.port}
    lease-renewal-interval-in-seconds: 5
    lease-expiration-duration-in-seconds: 12
```

### Parámetros de `Spring Cloud LoadBalancer` (en `api-gateway` y `ms-transacciones`)
```yaml
spring:
  cloud:
    loadbalancer:
      cache:
        ttl: 3s
```
Con `registry-fetch-interval-seconds: 5` y `loadbalancer.cache.ttl: 3s`, tras detener `ms-cuentas-2` (`P03`), la caché de instancias del Gateway y de `ms-transacciones` converge hacia `ms-cuentas-1` en la ventana esperada (`~3–6s` en apagado limpio, hasta `~12–15s` en caída abrupta).

---

## 3. Diseño de `api-gateway` (`:8080`)

### Enrutamiento Declarativo (`application.yml`)
```yaml
server:
  port: 8080

spring:
  application:
    name: api-gateway
  cloud:
    gateway:
      discovery:
        locator:
          enabled: false
      routes:
        - id: cuentas-db-estado
          uri: lb://ms-cuentas
          predicates:
            - Path=/api/cuentas/db/{segment}
          filters:
            - SetPath=/api/db/{segment}

        - id: cuentas-api
          uri: lb://ms-cuentas
          predicates:
            - Path=/api/cuentas/**

        - id: transacciones-db-estado
          uri: lb://ms-transacciones
          predicates:
            - Path=/api/transacciones/db/{segment}
          filters:
            - SetPath=/api/db/{segment}

        - id: transacciones-api
          uri: lb://ms-transacciones
          predicates:
            - Path=/api/transacciones/**
```

> **Orden de rutas:** `cuentas-db-estado` y `transacciones-db-estado` se declaran **antes** de las rutas wildcard `/**` para que `SetPath=/api/db/{segment}` capture `/api/cuentas/db/estado` y `/api/transacciones/db/estado` correctamente.

### Diseño de `GatewayTraceGlobalFilter`
Implementa `GlobalFilter` y `Ordered` (`Ordered.LOWEST_PRECEDENCE` o `Ordered.HIGHEST_PRECEDENCE` antes de escribir headers de respuesta):
- Añade `X-Gateway-Handled: api-gateway` a la respuesta HTTP saliente (`exchange.getResponse().getHeaders().add(...)`).
- Preserva íntegramente las cabeceras entrantes del cliente (en particular `X-Consistencia: CRITICA`) y las cabeceras devueltas por el microservicio (`X-Service-Instance`, `X-Db-Node`, `X-Db-Fallback`).
