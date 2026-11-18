# 1.1 Propósito y Alcance del Sistema

## 1. Propósito

Este documento especifica los requisitos funcionales, no funcionales, de interfaz y de verificación para el **Sistema Distribuido de Billetera Digital y Transferencias P2P**, diseñado bajo principios de **alta disponibilidad parcial**, **descubrimiento dinámico de servicios**, **balanceo de carga HTTP**, **separación de lecturas y escrituras (CQRS ligero)** y **consistencia fuerte tras escritura (*Read-Your-Own-Writes*)**.

El SRS sirve como contrato técnico entre el equipo de desarrollo, la documentación del repositorio y los criterios de evaluación experimental (**P01–P08**).

---

## 2. Alcance del Producto

### Qué incluye el sistema
1. **Puerta de enlace única (`api-gateway`, puerto `8080`):** Enrutamiento HTTP hacia microservicios descubiertos por nombre lógico (`lb://ms-cuentas`, `lb://ms-transacciones`).
2. **Registro y descubrimiento dinámico (`eureka-server`, puerto `8761`):** Autoregistro de instancias, *heartbeats*, expulsión de instancias caídas y actualización dinámica del registro.
3. **Microservicio de Cuentas (`ms-cuentas`, 2 instancias en puertos `8081` y `8082`):**
   - Consulta de perfil/saldo ordinario y contactos frecuentes (enrutados a réplicas PostgreSQL).
   - Consulta crítica de saldo inmediato post-transferencia (enrutada al nodo Primario).
   - Procesamiento atómico de débito/crédito interno con validación de estado (`ACTIVA`), saldo disponible y límite diario (`consumido_hoy + monto <= limite_diario`).
4. **Microservicio de Transacciones (`ms-transacciones`, puerto `8083`):**
   - Ejecución de transferencias P2P entre números celulares invocando a `ms-cuentas` por nombre lógico vía `@LoadBalanced`.
   - Registro del libro mayor de transacciones (`EXITOSA` / `RECHAZADA`) y emisión de comprobante único (`TX-...`).
   - Consulta de historial mensual (réplicas) y consulta crítica de comprobante recién emitido (Primario).
5. **Persistencia replicada PostgreSQL 17 (1 Primario + 2 Réplicas WAL):**
   - Aislamiento lógico/físico por esquemas (`cuentas_db` y `tx_db`) y roles independientes.
   - Enrutador programático (`CustomRoutingDataSource` sobre `AbstractRoutingDataSource`) con chequeo activo de salud, *failover* automático ante caída de una réplica y reincorporación condicionada.
6. **Despliegue reproducible con Docker Compose:** Orquestación completa de los 8 contenedores en red interna aislada y variables externalizadas en `.env`.

### Qué queda explícitamente fuera del alcance
- Pasarelas bancarias externas reales, autenticación OAuth2/JWT con proveedor de identidad externo o KYC biométrico.
- Promoción automática del nodo Primario (*failover* automático de escritura / Patroni / Raft).
- Sagas coreografiadas con *message brokers* (RabbitMQ/Kafka) o transacciones distribuidas 2PC/XA.

---

## 3. Justificación del Dominio Fintech

En sistemas financieros digitales, las anomalías de consistencia eventual tienen impacto directo sobre la integridad del dinero:

- **Riesgo de doble gasto (*double-spending*) percibido:** Si un usuario transfiere `$25.00` y al volver a la pantalla principal lee un saldo antiguo desde una réplica con retraso WAL (*replication lag*), el usuario percibe que conserva el saldo anterior y podría intentar reutilizarlo.
- **Solución adoptada:** Separación explícita entre **lecturas ordinarias tolerantes a retraso breve** (historial del mes, contactos frecuentes, consultas informativas → Réplicas 1 y 2) y **lecturas críticas post-escritura** (`saldo-critico`, `comprobante/{codigo}` → Primario).
