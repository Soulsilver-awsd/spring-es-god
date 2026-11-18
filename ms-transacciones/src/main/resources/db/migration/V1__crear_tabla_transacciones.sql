-- Libro mayor de transferencias P2P (propiedad exclusiva de ms-transacciones).
-- Las cuentas se referencian por celular como identificador de negocio, sin FK inter-esquema.
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

-- Consecutivo de comprobantes (TX-<anio>-<secuencia>): unico y seguro ante instancias concurrentes.
CREATE SEQUENCE IF NOT EXISTS tx_db.seq_codigo_comprobante START WITH 1 INCREMENT BY 1;
