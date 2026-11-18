# 6.2 Matriz de Trazabilidad Completa

Esta matriz enlaza cada requisito del SRS con su componente propietario, el escenario experimental **P01–P08** que lo valida y el criterio de la rúbrica de evaluación (100 puntos).

| ID Requisito | Título Resumido | Componente(s) | Prueba(s) | Criterio de Rúbrica (Pts) |
|---|---|---|---|---|
| `RF-01` | Consulta ordinaria de cuenta y saldo | `ms-cuentas`, `common-persistence` | `P01`, `P02`, `P05` | Arquitectura (15) / Enrutamiento DB (20) |
| `RF-02` | Consulta de contactos frecuentes | `ms-cuentas`, `common-persistence` | `P05`, `P06` | Enrutamiento DB (20) |
| `RF-03` | Lectura crítica de saldo inmediato | `ms-cuentas`, `common-persistence` | `P07` | Enrutamiento DB (20) |
| `RF-04` | Movimiento interno atómico débito/crédito | `ms-cuentas` | `P04`, `P07` | Arquitectura (15) / Enrutamiento DB (20) |
| `RF-05` | Alta de cuenta y endpoint `/instancia` | `ms-cuentas` | `P02`, `P03` | Gateway y balanceo (15) |
| `RF-06` | Orquestación de transferencia P2P (`lb://`) | `ms-transacciones`, `eureka-server` | `P04` | Arquitectura (15) / Eureka (15) |
| `RF-07` | Consulta de historial de movimientos | `ms-transacciones`, `common-persistence` | `P05`, `P06`, `P08` | Enrutamiento DB (20) |
| `RF-08` | Verificación crítica de comprobante | `ms-transacciones`, `common-persistence` | `P07` | Enrutamiento DB (20) |
| `RF-09` | Observabilidad `/api/db/estado` | `common-persistence` | `P05`, `P06`, `P08` | Evidencias y documentación (15) |
| `RF-10` | Registro dinámico y evicción en Eureka | `eureka-server`, todos los MS | `P01`, `P03` | Eureka y descubrimiento (15) |
| `RF-11` | Enrutamiento Gateway por `lb://` | `api-gateway` | `P01`, `P02`, `P03` | Gateway y balanceo HTTP (15) |
| `RF-12` | Auditoría real en `ApiResponse<T>` | `common-persistence`, ambos MS | `P02`–`P08` | Evidencias y documentación (15) |
| `RNF-01` | Balanceo HTTP equitativo (100+ req) | `api-gateway`, `ms-cuentas` ×2 | `P02` | Gateway y balanceo HTTP (15) |
| `RNF-02` | Continuidad ante caída de instancia | `eureka-server`, `api-gateway` | `P03` | Manejo de fallos y recuperación (20) |
| `RNF-03` | Failover de réplica PostgreSQL sin corte | `common-persistence`, `replica1/2` | `P06` | Manejo de fallos y recuperación (20) |
| `RNF-04` | Reincorporación segura tras 2 chequeos | `common-persistence`, `replica1` | `P08` | Manejo de fallos y recuperación (20) |
| `RNF-05` | `AbstractRoutingDataSource` + AOP pre-TX | `common-persistence` | `P05`, `P07` | Enrutamiento DB (20) |
| `RNF-06` | Consistencia fuerte RYOW post-transferencia | `common-persistence`, `ms-cuentas` | `P07` | Enrutamiento DB (20) |
| `RNF-07` | Distribución Round-Robin en réplicas | `common-persistence` | `P05`, `P08` | Enrutamiento DB (20) |
| `RNF-08` | Aislamiento `cuentas_db`/`tx_db` y WAL | `primary-init.sh`, `docker-compose.yml` | `P04`–`P08` | Arquitectura (15) |
| `RNF-09` | Sin secretos en repositorio (`.env`) | `.env.example`, `.gitignore` | Revisión | Evidencias y documentación (15) |
| `RNF-10` | Reproducibilidad total Docker Compose | `docker-compose.yml`, `README.md` | `P01`–`P08` | Evidencias y documentación (15) |
| `RNF-11` | Trazabilidad real `inet_server_addr()` | `common-persistence` | `P02`–`P08` | Evidencias y documentación (15) |
| `RNF-12` | Documentación modular y colecciones | `README.md`, `docs/srs/*` | Revisión | Evidencias y documentación (15) |
