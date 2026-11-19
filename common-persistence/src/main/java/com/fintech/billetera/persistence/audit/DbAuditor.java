package com.fintech.billetera.persistence.audit;

import com.fintech.billetera.persistence.routing.DbContextHolder;
import com.fintech.billetera.persistence.routing.DbKey;
import com.fintech.billetera.persistence.routing.PoliticaEnrutamiento;
import java.util.Optional;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Consulta la IP real del servidor PostgreSQL y su estado de recuperacion sobre la conexion activa.
 */
public class DbAuditor {

    private static final String AUDIT_SQL =
            "SELECT COALESCE(host(inet_server_addr()), '127.0.0.1') AS server_ip, "
                    + "inet_server_port() AS server_port, "
                    + "pg_is_in_recovery() AS in_recovery";

    private final JdbcTemplate jdbcTemplate;
    private final String servicioOrigen;

    public DbAuditor(JdbcTemplate jdbcTemplate, String servicioOrigen) {
        this.jdbcTemplate = jdbcTemplate;
        this.servicioOrigen = servicioOrigen;
    }

    public AuditoriaTecnicaDto capturarAuditoriaActual() {
        return capturarAuditoriaActual(null);
    }

    public AuditoriaTecnicaDto capturarAuditoriaActual(String instanciaCuentasConsultada) {
        DbKey dbKey = Optional.ofNullable(DbContextHolder.getDbKey()).orElse(DbKey.PRIMARY);
        PoliticaEnrutamiento politica = Optional.ofNullable(DbContextHolder.getPolicy())
                .orElse(PoliticaEnrutamiento.ESCRITURA_DIRECTA);

        String nodoDescripcion = jdbcTemplate.queryForObject(AUDIT_SQL, (rs, rowNum) -> {
            String ip = rs.getString("server_ip");
            int port = rs.getInt("server_port");
            boolean inRecovery = rs.getBoolean("in_recovery");
            return String.format("%s (%s:%d, recovery=%s)", dbKey.name(), ip, port, inRecovery);
        });

        return new AuditoriaTecnicaDto(
                servicioOrigen,
                instanciaCuentasConsultada,
                nodoDescripcion,
                politica
        );
    }

    public AuditoriaTecnicaDto auditoriaSinConsultaSql(String instanciaCuentasConsultada) {
        DbKey dbKey = Optional.ofNullable(DbContextHolder.getDbKey()).orElse(DbKey.PRIMARY);
        PoliticaEnrutamiento politica = Optional.ofNullable(DbContextHolder.getPolicy())
                .orElse(PoliticaEnrutamiento.ESCRITURA_DIRECTA);
        return new AuditoriaTecnicaDto(
                servicioOrigen,
                instanciaCuentasConsultada,
                dbKey.name(),
                politica
        );
    }

    public String getServicioOrigen() {
        return servicioOrigen;
    }
}
