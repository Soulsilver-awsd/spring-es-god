-- Migracion inmutable: no editar una vez aplicada (crear V3__... para cambios futuros).
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
