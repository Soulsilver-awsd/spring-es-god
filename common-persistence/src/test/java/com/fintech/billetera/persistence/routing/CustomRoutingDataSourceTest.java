package com.fintech.billetera.persistence.routing;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class CustomRoutingDataSourceTest {

    @AfterEach
    void cleanup() {
        DbContextHolder.clear();
    }

    @Test
    void defaultsToPrimaryWhenContextIsEmptyAndReturnsCurrentKeyWhenSet() {
        CustomRoutingDataSource ds = new CustomRoutingDataSource();
        assertThat(ds.determineCurrentLookupKey()).isEqualTo(DbKey.PRIMARY);

        DbContextHolder.set(DbKey.REPLICA_2, PoliticaEnrutamiento.ROUND_ROBIN_REPLICA, false);
        assertThat(ds.determineCurrentLookupKey()).isEqualTo(DbKey.REPLICA_2);

        DbContextHolder.clear();
        assertThat(ds.determineCurrentLookupKey()).isEqualTo(DbKey.PRIMARY);
    }
}
