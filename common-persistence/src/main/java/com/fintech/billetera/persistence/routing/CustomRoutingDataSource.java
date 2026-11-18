package com.fintech.billetera.persistence.routing;

import java.util.Optional;
import org.springframework.jdbc.datasource.lookup.AbstractRoutingDataSource;

/**
 * Enrutador JDBC programatico que delega la seleccion del pool Hikari
 * al valor fijado en DbContextHolder antes de iniciar la transaccion.
 */
public class CustomRoutingDataSource extends AbstractRoutingDataSource {

    @Override
    protected Object determineCurrentLookupKey() {
        return Optional.ofNullable(DbContextHolder.getDbKey()).orElse(DbKey.PRIMARY);
    }
}
