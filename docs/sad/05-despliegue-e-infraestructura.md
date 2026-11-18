# 5. Vista de Despliegue e Infraestructura (C4 · Deployment)

**Documentos relacionados:** [Índice del SAD](README.md) · [Nivel 2: Contenedores](02-contenedores-c4-nivel2.md) · [Docker Compose](../../docker-compose.yml) · [Script Primario](../../primary-init.sh) · [Script Réplica](../../start-replica.sh)

---

## 1. Diagrama C4 de Despliegue (Entorno Docker Compose)

```mermaid
flowchart TB
    Host["[Deployment Node] Host Anfitrion\nDocker Engine + Docker Compose v2\nArchivo .env (derivado de .env.example)"]

    subgraph DockerEngine["[Container Runtime] Red Interna Aislada Docker"]
        subgraph AppNodes["Nodos de Aplicacion (Imagenes JDK 21 Alpine Multi-Etapa)"]
            EU["[Container] eureka-server\nHost:8761 -> Contenedor:8761"]
            GW["[Container] api-gateway\nHost:8080 -> Contenedor:8080\ndepends_on: eureka-server"]
            CTA1["[Container] ms-cuentas-1\nHost:8081 -> Contenedor:8081\ndepends_on: primary, eureka"]
            CTA2["[Container] ms-cuentas-2\nHost:8082 -> Contenedor:8082\ndepends_on: primary, eureka"]
            TRX["[Container] ms-transacciones\nHost:8083 -> Contenedor:8083\ndepends_on: primary, eureka"]
        end

        subgraph DbNodes["Nodos PostgreSQL 17 (WAL Streaming)"]
            PGP["[Container] primary\nHost:5432 -> Contenedor:5432\nwal_level=replica, max_wal_senders=10,\nwal_keep_size=256MB, hot_standby=on"]
            PGR1["[Container] replica1\nHost:5433 -> Contenedor:5432\nentrypoint: start-replica.sh"]
            PGR2["[Container] replica2\nHost:5434 -> Contenedor:5432\nentrypoint: start-replica.sh"]

            V0[("Volumen: primary_data")]
            V1[("Volumen: replica1_data")]
            V2[("Volumen: replica2_data")]

            PGP --- V0
            PGR1 --- V1
            PGR2 --- V2
        end
    end

    Host --> DockerEngine
    PGP == "pg_basebackup + WAL TCP :5432" ==> PGR1
    PGP == "pg_basebackup + WAL TCP :5432" ==> PGR2
```

---

## 2. Secuencia de Arranque y Dependencias (`depends_on` + `healthcheck`)

Para cumplir con `RNF-10` (reproducibilidad limpia en un solo comando `docker compose up -d --build`), la orquestación impone un grafo de dependencias determinístico:

```mermaid
flowchart LR
    P["1. primary healthy\n(pg_isready -U admin -d laboratorio)"] --> R1["2a. replica1\n(pg_basebackup -> hot_standby)"]
    P --> R2["2b. replica2\n(pg_basebackup -> hot_standby)"]
    P --> CTA1["3a. ms-cuentas-1\n(Flyway advisory lock)"]
    P --> CTA2["3b. ms-cuentas-2\n(espera lock Flyway)"]
    P --> TRX["3c. ms-transacciones\n(Flyway tx_db)"]
    EU["1b. eureka-server healthy\n(GET /actuator/health)"] --> CTA1
    EU --> CTA2
    EU --> TRX
    EU --> GW["4. api-gateway\n(:8080 listo para trafico)"]
```

### Protección contra condiciones de carrera en arranque
- **Base de datos:** `primary-init.sh` crea el rol `replicator` con autenticación `scram-sha-256` e inicializa esquemas/roles de aplicación (`cuentas_db`/`cuentas_user`, `tx_db`/`tx_user`). `start-replica.sh` espera en bucle hasta que `pg_basebackup` complete una copia física limpia si `$PGDATA/PG_VERSION` no existe.
- **Microservicios duplicados (`ms-cuentas-1` y `ms-cuentas-2`):** Como ambas instancias arrancan en paralelo apuntando al mismo esquema `cuentas_db` en `primary`, el versionamiento de tablas y datos semilla se gestiona mediante **Flyway** (`@FlywayDataSource` sobre `PRIMARY`), el cual utiliza internamente un **PostgreSQL *advisory lock*** para garantizar que una sola instancia aplique las migraciones (`V1__`, `V2__`) y la segunda valide sin errores de unicidad ni condiciones de carrera.

---

## 3. Seguridad y Parametrización de Entorno (`RNF-09`)

- **Compilación autocontenida:** Cada servicio Java se construye mediante `Dockerfile` multi-etapa (`maven:3.9-eclipse-temurin-21-alpine` en fase *build* → `eclipse-temurin:21-jre-alpine` en fase *runtime*), eliminando la dependencia de JDK/Maven en el host.
- **Externalización de secretos:** Las credenciales (`POSTGRES_PASSWORD`, `REPLICATION_PASSWORD`, `CUENTAS_DB_PASSWORD`, `TX_DB_PASSWORD`) se definen en `.env` (ignorado en `.gitignore`) y se documentan con valores plantilla en `.env.example`.
- **Principio de mínimo privilegio en SQL:**
  - `cuentas_user` solo tiene privilegios sobre `cuentas_db`.
  - `tx_user` solo tiene privilegios sobre `tx_db`.
  - `replicator` posee únicamente permiso `REPLICATION LOGIN` para transmisión WAL.
