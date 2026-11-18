# 1. Estructura de Proyectos, Módulos Maven y Paquetes

**Documentos relacionados:** [Índice del SDD](README.md) · [Nivel 2 SAD](../sad/02-contenedores-c4-nivel2.md) · [Nivel 3 SAD](../sad/03-componentes-c4-nivel3.md)

---

## 1. Diseño del Repositorio Multi-Módulo (`pom.xml` Padre)

El proyecto se organiza como un agregador Maven único para compilar todos los artefactos de forma consistente dentro de Docker o en local con Java 21:

```text
spring-es-god/
├── pom.xml                                  # POM padre (Spring Boot 3.4.3 + Spring Cloud 2024.0.1)
├── .env.example                             # Plantilla pública de variables sin secretos reales
├── .gitignore                               # Excluye .env, target/, logs/
├── docker-compose.yml                       # Orquestación de los 8 contenedores
├── primary-init.sh                          # Inicialización de replicación y esquemas/roles
├── start-replica.sh                         # Arranque pg_basebackup + hot_standby
├── common-persistence/
│   ├── pom.xml
│   └── src/main/java/com/fintech/billetera/persistence/...
├── eureka-server/
│   ├── pom.xml
│   ├── Dockerfile
│   └── src/main/java/com/fintech/billetera/eureka/...
├── api-gateway/
│   ├── pom.xml
│   ├── Dockerfile
│   └── src/main/java/com/fintech/billetera/gateway/...
├── ms-cuentas/
│   ├── pom.xml
│   ├── Dockerfile
│   └── src/main/
│       ├── java/com/fintech/billetera/cuentas/...
│       └── resources/db/migration/          # V1__, V2__ (Flyway sobre cuentas_db)
├── ms-transacciones/
│   ├── pom.xml
│   ├── Dockerfile
│   └── src/main/
│       ├── java/com/fintech/billetera/transacciones/...
│       └── resources/db/migration/          # V1__ (Flyway sobre tx_db)
├── scripts/                                 # Automatización de pruebas P01-P08
└── docs/
    ├── srs/                                 # Requisitos IEEE 29148
    ├── sad/                                 # Arquitectura C4 + ADRs
    └── sdd/                                 # Diseño detallado IEEE 1016
```

---

## 2. Versiones y Gestión de Dependencias (`pom.xml` Raíz)

| Propiedad / Dependencia | Valor Fijado | Justificación |
|---|---|---|
| `java.version` | `21` | LTS requerido (`Virtual Threads` opcionales, `records` Java para DTOs). |
| `spring-boot-starter-parent` | `3.4.3` | Base común de Spring Boot, HikariCP, AOP y Actuator. |
| `spring-cloud.version` | `2024.0.1` | Compatibilidad oficial con Spring Boot `3.4.x` (`Gateway`, `Eureka`, `LoadBalancer`). |
| `org.postgresql:postgresql` | Gestionada por Boot BOM | Driver JDBC oficial PostgreSQL 17 con soporte `scram-sha-256`. |
| `org.flywaydb:flyway-core` + `flyway-database-postgresql` | Gestionada por Boot BOM | Versionamiento SQL de esquemas y migraciones seguras con *advisory lock* nativo. |
| `spring-boot-starter-validation` | Gestionada por Boot BOM | Validación declarativa Jakarta (`@NotBlank`, `@DecimalMin`, `@Positive`). |

---

## 3. Convención Detallada de Paquetes Java

### `common-persistence` (`com.fintech.billetera.persistence`)
- `annotation/`: `UsarNodo`, `TipoNodo`
- `routing/`: `DbKey`, `PoliticaEnrutamiento`, `DbContextHolder`, `CustomRoutingDataSource`, `DbRoutingAspect`
- `health/`: `ReplicaHealthTracker`, `ReplicaStatus`
- `audit/`: `DbAuditor`, `AuditoriaTecnicaDto`, `ApiResponse<T>`, `DbEstadoController`, `DbEstadoResponse`
- `config/`: `MultiNodeDataSourceConfig`, `PersistenceRoutingProperties`
- `exception/`: `BaseErrorHandler`, `ServiceUnavailableException`

### `ms-cuentas` (`com.fintech.billetera.cuentas`)
- `domain/`: `Cuenta`, `ContactoFrecuente`, `EstadoCuenta`
- `repository/`: `CuentaRepository`, `ContactoFrecuenteRepository`
- `service/`: `CuentaConsultaService`, `MovimientoCuentaService`
- `web/`: `CuentaController`, `CuentasExceptionHandler`, DTOs (`CuentaDto`, `ContactoDto`, `SaldoCriticoDto`, `MovimientoInternoRequest`, `MovimientoInternoResponse`, `CrearCuentaRequest`)
- `resources/db/migration/`: migraciones Flyway `V1__crear_tablas_cuentas.sql`, `V2__insertar_datos_semilla.sql`

### `ms-transacciones` (`com.fintech.billetera.transacciones`)
- `config/`: `RestClientConfig` (`@LoadBalanced RestClient.Builder`)
- `domain/`: `Transaccion`, `EstadoTransaccion`
- `repository/`: `TransaccionRepository`
- `client/`: `CuentasHttpClient`
- `service/`: `TransferenciaOrchestratorService`, `TransaccionConsultaService`
- `web/`: `TransaccionController`, `TransaccionesExceptionHandler`, DTOs (`TransferenciaRequest`, `ComprobanteDto`, `TransaccionDto`)

### `api-gateway` (`com.fintech.billetera.gateway`)
- `ApiGatewayApplication`
- `filter/`: `GatewayTraceGlobalFilter`

### `eureka-server` (`com.fintech.billetera.eureka`)
- `EurekaServerApplication`

---

## 4. Propiedades Comunes de Spring Boot en Microservicios de Negocio

Tanto `ms-cuentas` como `ms-transacciones` deben fijar obligatoriamente:

```yaml
spring:
  jpa:
    open-in-view: false
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
```

- **`open-in-view: false`**: evita que Hibernate abra una sesión/conexión en `PRIMARY` antes de invocar la capa de servicio anotada con `@UsarNodo`.
- **`ddl-auto: validate`**: impide que Hibernate modifique el esquema; toda evolución DDL y datos semilla se versiona mediante migraciones SQL de **Flyway** ejecutadas sobre `PRIMARY` con *advisory lock* nativo.
