# 7. Diseño de Docker, Parametrización `.env` y Verificación `P01–P08`

**Documentos relacionados:** [Índice del SDD](README.md) · [Despliegue SAD](../sad/05-despliegue-e-infraestructura.md) · [Criterios `P01–P08`](../srs/06-verificacion-y-trazabilidad/01-criterios-aceptacion-p01-p08.md) · [Docker Compose actual](../../docker-compose.yml)

---

## 1. Plantilla `.env.example` (Sin Secretos Reales)

El repositorio versionará `.env.example` e incluirá `.env` en `.gitignore`:

```dotenv
# PostgreSQL Cluster
POSTGRES_DB=laboratorio
POSTGRES_USER=admin
POSTGRES_PASSWORD=CAMBIAR_PASSWORD_ADMIN
REPLICATION_PASSWORD=CAMBIAR_PASSWORD_REPLICADOR

# Esquemas y usuarios por microservicio
CUENTAS_DB_USER=cuentas_user
CUENTAS_DB_PASSWORD=CAMBIAR_PASSWORD_CUENTAS
TX_DB_USER=tx_user
TX_DB_PASSWORD=CAMBIAR_PASSWORD_TX
```

---

## 2. Diseño de `Dockerfile` Multi-Etapa (Servicios Java)

Para cumplir con `RNF-10` (compilación independiente del host usando Java 21 + Maven dentro de Docker):

```dockerfile
# Etapa 1: compilacion del modulo y dependencias
FROM maven:3.9-eclipse-temurin-21-alpine AS builder
WORKDIR /workspace
COPY pom.xml .
COPY common-persistence/pom.xml common-persistence/
COPY eureka-server/pom.xml eureka-server/
COPY api-gateway/pom.xml api-gateway/
COPY ms-cuentas/pom.xml ms-cuentas/
COPY ms-transacciones/pom.xml ms-transacciones/
COPY common-persistence/src common-persistence/src
COPY <SERVICIO>/src <SERVICIO>/src
RUN mvn -pl <SERVICIO> -am clean package -DskipTests

# Etapa 2: imagen minima de ejecucion
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN apk add --no-cache curl
COPY --from=builder /workspace/<SERVICIO>/target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
```

---

## 3. Diseño de Orquestación Completa en `docker-compose.yml`

Topología de los 8 servicios sobre red puente común (`wallet-net`), ampliando el clúster PostgreSQL ya existente en [docker-compose.yml](../../docker-compose.yml):

| Servicio Compose | Imagen / Build | Puerto Host | `depends_on` (`condition`) | `healthcheck` |
|---|---|---|---|---|
| `primary` | `postgres:17` | `5432:5432` | — | `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}` |
| `replica1` | `postgres:17` | `5433:5432` | `primary` (`service_healthy`) | `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}` |
| `replica2` | `postgres:17` | `5434:5432` | `primary` (`service_healthy`) | `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}` |
| `eureka-server` | `./eureka-server` | `8761:8761` | — | `curl -sf http://localhost:8761/actuator/health` |
| `ms-cuentas-1` | `./ms-cuentas` | `8081:8081` | `primary` (`healthy`), `eureka-server` (`healthy`) | `curl -sf http://localhost:8081/actuator/health` |
| `ms-cuentas-2` | `./ms-cuentas` | `8082:8082` | `primary` (`healthy`), `eureka-server` (`healthy`) | `curl -sf http://localhost:8082/actuator/health` |
| `ms-transacciones` | `./ms-transacciones` | `8083:8083` | `primary` (`healthy`), `eureka-server` (`healthy`) | `curl -sf http://localhost:8083/actuator/health` |
| `api-gateway` | `./api-gateway` | `8080:8080` | `eureka-server` (`healthy`) | `curl -sf http://localhost:8080/actuator/health` |

---

## 4. Diseño de Verificación Automatizada (`scripts/` para `P01–P08`)

Para asegurar reproducibilidad y evidencia objetiva durante la defensa técnica, las pruebas `P01–P08` se ejecutarán directamente con **`curl`** (sin Postman) mediante guías y scripts ejecutables en [docs/api/](../api/README.md):

| Prueba | Script / Flujo Automatizado | Aserción Esperada |
|---|---|---|
| `P01` | Consulta `GET :8761/eureka/apps` + `GET :8080/api/cuentas/0991112233` | `MS-CUENTAS` (2 `UP`), `MS-TRANSACCIONES` (1 `UP`) y `200 OK` vía Gateway. |
| `P02` | Bucle de `120` peticiones `GET :8080/api/cuentas/instancia` contabilizando `X-Service-Instance` | `120/120` respuestas `200 OK` y reparto ~`60 / 60` entre `ms-cuentas-1` y `ms-cuentas-2`. |
| `P03` | Ráfaga continua mientras se ejecuta `docker compose stop ms-cuentas-2` y luego `start` | Convergencia hacia `ms-cuentas-1` y reincorporación automática al reiniciar. |
| `P04` | `POST :8080/api/transacciones/transferir` válido (`25.00`) + inválido (`9999.00`) | `201 Created` con `instanciaCuentasConsultada` + rechazo `409` sin alterar saldos. |
| `P05` | `20` lecturas ordinarias + consulta `GET :8080/api/cuentas/db/estado` | Reparto ~`10` en `REPLICA_1` y ~`10` en `REPLICA_2` (`recovery=true`). |
| `P06` | `docker compose stop replica1` + `20` lecturas ordinarias + `/db/estado` | `0` errores HTTP; `REPLICA_1 available=false`; `100%` en `REPLICA_2`. |
| `P07` | Transferencia `25.00` seguida de `GET .../saldo-critico` y `GET .../comprobante/{codigo}` | `politicaEnrutamiento = LECTURA_CRITICA_PRIMARIO`, `recovery=false`, saldo exacto. |
| `P08` | `docker compose start replica1` + espera `~6–10s` + `/db/estado` + `20` lecturas | `REPLICA_1 available=true` tras `2/2` sondeos y retorno al balanceo *Round-Robin*. |
