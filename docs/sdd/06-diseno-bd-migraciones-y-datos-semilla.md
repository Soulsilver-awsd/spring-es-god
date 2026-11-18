# 6. Diseño de Base de Datos, Versionamiento (Flyway), Índices y Semillas

**Documentos relacionados:** [Índice del SDD](README.md) · [Modelo de Datos SRS](../srs/05-interfaces-y-datos/02-modelo-datos-esquemas.md) · [Despliegue SAD](../sad/05-despliegue-e-infraestructura.md) · [ADR-008 Flyway](../sad/06-adrs-decisiones-arquitectonicas.md) · [Script Primario](../../primary-init.sh)

---

## 1. Estrategia de Inicialización vs. Versionamiento de Esquema

Se separa claramente la responsabilidad entre infraestructura PostgreSQL y evolución versionada del esquema por microservicio:

1. **Capa de infraestructura ([primary-init.sh](../../primary-init.sh)):** Se ejecuta una única vez al crear el volumen `primary_data` para crear los roles (`replicator`, `cuentas_user`, `tx_user`), habilitar `scram-sha-256` en `pg_hba.conf` y crear los esquemas disjuntos `cuentas_db` y `tx_db`.
2. **Capa de aplicación (**Flyway**):** Cada microservicio gestiona y versiona sus propias tablas, restricciones, índices y datos semilla dentro de su esquema privado mediante archivos SQL inmutables en `src/main/resources/db/migration/`, ejecutados únicamente sobre `PRIMARY` gracias al bean `@FlywayDataSource` de `common-persistence`.
3. **Propagación a réplicas:** Al ejecutarse las migraciones sobre `PRIMARY`, PostgreSQL registra el DDL y los `INSERT` en el *Write-Ahead Log* (WAL) y los replica físicamente hacia `replica1` y `replica2`.

---

## 2. Configuración de Flyway por Microservicio

### En `ms-cuentas` (`application.yml`)
```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    schemas: cuentas_db
    default-schema: cuentas_db
    table: flyway_schema_history
    baseline-on-migrate: false
    validate-on-migrate: true
```

### En `ms-transacciones` (`application.yml`)
```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    schemas: tx_db
    default-schema: tx_db
    table: flyway_schema_history
    baseline-on-migrate: false
    validate-on-migrate: true
```

> **Aislamiento de historial:** Existen dos tablas de historial totalmente independientes: `cuentas_db.flyway_schema_history` y `tx_db.flyway_schema_history`. Ningún servicio conoce ni altera las migraciones del otro.

---

## 3. Migraciones Versionadas Exactas

### Convención de nombres e inmutabilidad
- Formato obligatorio: `V<version>__<descripcion_snake_case>.sql` (doble guion bajo `__`).
- **Regla de inmutabilidad:** Una vez aplicada una migración (`checksum` registrado en `flyway_schema_history`), **nunca se edita**; cualquier cambio futuro (nueva columna, índice o ajuste de datos) debe crearse como una nueva versión (`V3__...sql`).

### Migraciones de `ms-cuentas` (`ms-cuentas/src/main/resources/db/migration/`)

#### `V1__crear_tablas_cuentas.sql`
```sql
CREATE TABLE IF NOT EXISTS cuentas_db.cuentas (
    id              BIGSERIAL PRIMARY KEY,
    numero_celular  VARCHAR(20) NOT NULL UNIQUE,
    titular         VARCHAR(120) NOT NULL,
    saldo           NUMERIC(14, 2) NOT NULL CHECK (saldo >= 0),
    limite_diario   NUMERIC(14, 2) NOT NULL CHECK (limite_diario > 0),
    consumido_hoy   NUMERIC(14, 2) NOT NULL DEFAULT 0.00 CHECK (consumido_hoy >= 0),
    estado          VARCHAR(20) NOT NULL DEFAULT 'ACTIVA'
                    CHECK (estado IN ('ACTIVA', 'BLOQUEADA'))
);

CREATE TABLE IF NOT EXISTS cuentas_db.contactos_frecuentes (
    id                    BIGSERIAL PRIMARY KEY,
    cuenta_propietario_id BIGINT NOT NULL REFERENCES cuentas_db.cuentas(id) ON DELETE CASCADE,
    celular_contacto      VARCHAR(20) NOT NULL,
    alias                 VARCHAR(80) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_contactos_propietario
    ON cuentas_db.contactos_frecuentes (cuenta_propietario_id);
```

#### `V2__insertar_datos_semilla.sql`
```sql
INSERT INTO cuentas_db.cuentas (numero_celular, titular, saldo, limite_diario, consumido_hoy, estado)
VALUES
    ('0991112233', 'Ana Torres', 500.00, 300.00, 0.00, 'ACTIVA'),
    ('0984445566', 'Luis Mendez', 150.00, 500.00, 0.00, 'ACTIVA'),
    ('0977778899', 'Carla Vega', 100.00, 50.00, 0.00, 'ACTIVA'),
    ('0960001122', 'Cuenta Bloqueada Demo', 200.00, 200.00, 0.00, 'BLOQUEADA')
ON CONFLICT (numero_celular) DO NOTHING;

INSERT INTO cuentas_db.contactos_frecuentes (cuenta_propietario_id, celular_contacto, alias)
SELECT c.id, v.celular_contacto, v.alias
FROM cuentas_db.cuentas c
JOIN (VALUES
    ('0984445566', 'Luis - Almuerzos'),
    ('0977778899', 'Carla - Oficina')
) AS v(celular_contacto, alias) ON TRUE
WHERE c.numero_celular = '0991112233'
  AND NOT EXISTS (
      SELECT 1 FROM cuentas_db.contactos_frecuentes cf
      WHERE cf.cuenta_propietario_id = c.id AND cf.celular_contacto = v.celular_contacto
  );
```

### Migraciones de `ms-transacciones` (`ms-transacciones/src/main/resources/db/migration/`)

#### `V1__crear_tabla_transacciones.sql`
```sql
CREATE TABLE IF NOT EXISTS tx_db.transacciones (
    id                  BIGSERIAL PRIMARY KEY,
    codigo_comprobante  VARCHAR(40) NOT NULL UNIQUE,
    celular_origen      VARCHAR(20) NOT NULL,
    celular_destino     VARCHAR(20) NOT NULL,
    monto               NUMERIC(14, 2) NOT NULL CHECK (monto > 0),
    motivo              VARCHAR(160) NOT NULL,
    estado              VARCHAR(20) NOT NULL CHECK (estado IN ('EXITOSA', 'RECHAZADA')),
    fecha_hora          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tx_origen_fecha
    ON tx_db.transacciones (celular_origen, fecha_hora DESC);

CREATE INDEX IF NOT EXISTS idx_tx_destino_fecha
    ON tx_db.transacciones (celular_destino, fecha_hora DESC);
```

---

## 4. Concurrencia de Arranque entre `ms-cuentas-1` y `ms-cuentas-2` (*Advisory Lock*)

`ms-cuentas-1` y `ms-cuentas-2` arrancan simultáneamente contra el mismo esquema `cuentas_db` en `PRIMARY`:
1. Flyway adquiere automáticamente un **PostgreSQL *advisory lock*** de sesión antes de evaluar `cuentas_db.flyway_schema_history`.
2. La primera instancia en obtener el *lock* aplica `V1` y `V2`, valida integridad y registra los *checksums*.
3. La segunda instancia espera la liberación del *lock*, lee `flyway_schema_history`, verifica que `V1` y `V2` ya están aplicadas (`Schema is up to date`) y arranca inmediatamente sin colisiones.
4. A continuación, Hibernate (`spring.jpa.hibernate.ddl-auto=validate`) valida las entidades JPA contra el esquema ya migrado.
