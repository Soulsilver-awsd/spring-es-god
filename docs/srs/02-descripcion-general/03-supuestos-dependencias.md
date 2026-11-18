# 2.3 Supuestos, Dependencias y Restricciones

## 1. Supuestos Operativos

1. El entorno anfitrión dispone de **Docker Engine** y **Docker Compose v2** con los puertos `5432`, `5433`, `5434`, `8080`, `8081`, `8082`, `8083` y `8761` libres.
2. El nodo `postgres-primary` permanece disponible durante las operaciones de escritura; las fallas simuladas en la capa de persistencia corresponden a la caída y recuperación de réplicas (`replica1` / `replica2`).
3. Las credenciales de base de datos se suministran mediante archivo `.env` local (copiado desde `.env.example`), nunca embebidas como secretos reales en el código fuente.

---

## 2. Dependencias Tecnológicas

- **Java 21 LTS** y **Maven 3.9+** (ejecutado dentro de imagen `maven:3.9-eclipse-temurin-21-alpine` para independencia del host).
- **Spring Boot 3.4.3** y **Spring Cloud 2024.0.1**.
- **PostgreSQL 17** con parámetros `wal_level=replica`, `max_wal_senders=10`, `wal_keep_size=256MB`, `hot_standby=on`.

---

## 3. Restricciones de Diseño Obligatorias

1. **Prohibición de acceso directo entre esquemas:** `ms-transacciones` no puede ejecutar consultas SQL sobre `cuentas_db.cuentas` ni `cuentas_db.contactos_frecuentes`. Toda consulta o modificación de saldo debe realizarse vía HTTP hacia `lb://ms-cuentas`.
2. **Prohibición de URLs fijas entre microservicios:** La comunicación inter-servicios debe usar descubrimiento dinámico por nombre lógico (`http://ms-cuentas/...`), nunca direcciones IP o puertos estáticos (`localhost:8081`).
3. **Prohibición de simulación de réplicas:** `replica1` y `replica2` deben ser contenedores PostgreSQL 17 independientes sincronizados vía WAL físico (`pg_basebackup` + *streaming replication*).
4. **Insuficiencia de `@Transactional(readOnly = true)`:** El balanceo y separación de lecturas/escrituras debe implementarse explícitamente mediante `AbstractRoutingDataSource` (o múltiples `DataSource` enrutados por política), nunca confiando únicamente en `readOnly = true`.
5. **Reproducibilidad y seguridad:** No se permiten contraseñas reales en Git ni pasos manuales no documentados para levantar el entorno.
