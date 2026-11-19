-- Migracion inmutable: no editar una vez aplicada (crear V3__... para cambios futuros).
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
