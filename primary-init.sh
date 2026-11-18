#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  -v db_name="$POSTGRES_DB" \
  -v repl_password="$REPLICATION_PASSWORD" \
  -v cuentas_user="$CUENTAS_DB_USER" \
  -v cuentas_password="$CUENTAS_DB_PASSWORD" \
  -v tx_user="$TX_DB_USER" \
  -v tx_password="$TX_DB_PASSWORD" <<'SQL'
-- Rol exclusivo para streaming WAL hacia las replicas
SELECT format('CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD %L', :'repl_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replicator') \gexec

-- Roles de aplicacion disjuntos por microservicio
SELECT format('CREATE ROLE %I WITH LOGIN PASSWORD %L', :'cuentas_user', :'cuentas_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'cuentas_user') \gexec

SELECT format('CREATE ROLE %I WITH LOGIN PASSWORD %L', :'tx_user', :'tx_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'tx_user') \gexec

-- Permisos de conexion a la base de datos
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'db_name', :'cuentas_user') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'db_name', :'tx_user') \gexec

-- Esquemas privados por servicio
SELECT format('CREATE SCHEMA IF NOT EXISTS cuentas_db AUTHORIZATION %I', :'cuentas_user') \gexec
SELECT format('CREATE SCHEMA IF NOT EXISTS tx_db AUTHORIZATION %I', :'tx_user') \gexec

-- Aislamiento estricto: revocar acceso publico y cruzado entre esquemas
REVOKE ALL ON SCHEMA cuentas_db FROM PUBLIC;
REVOKE ALL ON SCHEMA tx_db FROM PUBLIC;
SELECT format('REVOKE ALL ON SCHEMA cuentas_db FROM %I', :'tx_user') \gexec
SELECT format('REVOKE ALL ON SCHEMA tx_db FROM %I', :'cuentas_user') \gexec

SELECT format('GRANT USAGE, CREATE ON SCHEMA cuentas_db TO %I', :'cuentas_user') \gexec
SELECT format('GRANT USAGE, CREATE ON SCHEMA tx_db TO %I', :'tx_user') \gexec

-- search_path por defecto para cada rol
SELECT format('ALTER ROLE %I SET search_path TO cuentas_db', :'cuentas_user') \gexec
SELECT format('ALTER ROLE %I SET search_path TO tx_db', :'tx_user') \gexec
SQL

echo 'host replication replicator all scram-sha-256' >> "$PGDATA/pg_hba.conf"
