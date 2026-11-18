# 1.3 Referencias y Marco Técnico

## 1. Documentos de Referencia del Proyecto

1. **[Replicación y sincronización en PostgreSQL.md](../../../Replicación%20y%20sincronización%20en%20PostgreSQL.md):** Guía técnica base del clúster PostgreSQL 17 con 1 primario y 2 réplicas en modo *hot standby*, verificación de `pg_stat_replication` y comportamiento de replicación asíncrona.
2. **[docker-compose.yml](../../../docker-compose.yml)**, **[primary-init.sh](../../../primary-init.sh)** y **[start-replica.sh](../../../start-replica.sh):** Definición de infraestructura de base de datos, inicialización de roles y clonado base con `pg_basebackup`.
3. **Estándar ISO/IEC/IEEE 29148:2018:** *Systems and software engineering — Life cycle processes — Requirements engineering* (estructura y criterios de calidad de requisitos: verificables, no ambiguos, trazables).
4. **Documentación oficial de tecnologías:**
   - Spring Boot `3.4.x` (Data JPA, Web, AOP, Actuator)
   - Spring Cloud `2024.0.x` (Netflix Eureka, Gateway, LoadBalancer)
   - PostgreSQL `17` (*Streaming Replication* y *Hot Standby*)

---

## 2. Convenciones de Prioridad y Redacción de Requisitos

Cada requisito en este SRS sigue un identificador único:
- **`RF-XX`**: Requisito Funcional.
- **`RNF-XX`**: Requisito No Funcional.

Los niveles de prioridad utilizados son:
- **Crítica (Must):** Indispensable para el funcionamiento mínimo o exigido directamente por la rúbrica de evaluación.
- **Alta (Should):** Necesaria para observabilidad, resiliencia y defensa técnica sólida.
- **Media (Could):** Mejora operativa o de diagnóstico complementario.
