# 2.2 Funciones Principales del Sistema

## 1. Catálogo de Capacidades por Módulo

| Módulo | Capacidad Funcional | Estrategia de Datos / Red |
|---|---|---|
| **`api-gateway`** | Punto único de entrada HTTP (`:8080`), enrutamiento dinámico vía `lb://` y trazabilidad de gateway | WebFlux + Spring Cloud LoadBalancer |
| **`eureka-server`** | Registro de instancias, recepción de *heartbeats* y expulsión automática de instancias caídas | Eureka Server (`:8761`) |
| **`ms-cuentas` (×2)** | Consulta ordinaria de perfil y saldo (`GET /api/cuentas/{celular}`) | `@UsarNodo(REPLICA)` → Round-Robin `REPLICA_1` / `REPLICA_2` |
| **`ms-cuentas` (×2)** | Consulta de contactos frecuentes (`GET /api/cuentas/{celular}/contactos`) | `@UsarNodo(REPLICA)` → Round-Robin `REPLICA_1` / `REPLICA_2` |
| **`ms-cuentas` (×2)** | Consulta crítica de saldo inmediato (`GET /api/cuentas/{celular}/saldo-critico`) | `@UsarNodo(PRIMARY)` → Cero *replication lag* |
| **`ms-cuentas` (×2)** | Débito y crédito atómico interno (`POST /api/cuentas/movimiento-interno`) | `@UsarNodo(PRIMARY)` + `@Transactional` |
| **`ms-transacciones`** | Orquestación de transferencias P2P (`POST /api/transacciones/transferir`) | Llama a `lb://ms-cuentas` + escribe en `PRIMARY` |
| **`ms-transacciones`** | Consulta de historial de movimientos (`GET /api/transacciones/historial/{celular}`) | `@UsarNodo(REPLICA)` → Round-Robin `REPLICA_1` / `REPLICA_2` |
| **`ms-transacciones`** | Verificación inmediata de comprobante (`GET /api/transacciones/comprobante/{codigo}`) | `@UsarNodo(PRIMARY)` → Consistencia fuerte |
| **`common-persistence`** | Sondeo periódico de réplicas, *failover* ante caída, reincorporación segura y auditoría real con `inet_server_addr()` | `AbstractRoutingDataSource` + `@Scheduled(fixedDelay = 3000)` |
