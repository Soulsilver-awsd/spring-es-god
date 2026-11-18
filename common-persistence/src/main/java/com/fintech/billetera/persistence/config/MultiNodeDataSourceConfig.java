package com.fintech.billetera.persistence.config;

import com.fintech.billetera.persistence.health.ReplicaHealthTracker;
import com.fintech.billetera.persistence.routing.CustomRoutingDataSource;
import com.fintech.billetera.persistence.routing.DbKey;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import jakarta.annotation.PreDestroy;
import java.util.EnumMap;
import java.util.HashMap;
import java.util.Map;
import javax.sql.DataSource;
import org.springframework.boot.autoconfigure.flyway.FlywayDataSource;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

/**
 * Construye los tres pools HikariCP (PRIMARY, REPLICA_1, REPLICA_2), expone
 * CustomRoutingDataSource como DataSource principal y dirige Flyway exclusivamente a PRIMARY.
 */
@Configuration
public class MultiNodeDataSourceConfig {

    private final Map<DbKey, HikariDataSource> managedReplicaPools = new EnumMap<>(DbKey.class);
    private HikariDataSource primaryPool;

    @Bean
    @FlywayDataSource
    public DataSource flywayDataSource(PersistenceRoutingProperties properties) {
        return getOrCreatePrimaryPool(properties);
    }

    @Bean
    public ReplicaHealthTracker replicaHealthTracker(PersistenceRoutingProperties properties) {
        Map<DbKey, DataSource> replicaDataSources = new EnumMap<>(DbKey.class);
        for (PersistenceRoutingProperties.ReplicaNodeConfig replica : properties.getReplicas()) {
            if (replica.getKey() == null || replica.getKey() == DbKey.PRIMARY) {
                throw new IllegalArgumentException("Cada replica debe especificar key REPLICA_1 o REPLICA_2");
            }
            if (replica.getUrl() != null && !replica.getUrl().isBlank()) {
                HikariDataSource pool = buildPool(replica, true, "hikari-" + replica.getKey().name().toLowerCase());
                managedReplicaPools.put(replica.getKey(), pool);
                replicaDataSources.put(replica.getKey(), pool);
            }
        }
        return new ReplicaHealthTracker(
                replicaDataSources,
                properties.getRecoverySuccessThreshold(),
                properties.getProbeQueryTimeoutSeconds()
        );
    }

    @Bean
    @Primary
    public DataSource dataSource(
            PersistenceRoutingProperties properties,
            ReplicaHealthTracker replicaHealthTracker) {
        HikariDataSource primary = getOrCreatePrimaryPool(properties);

        Map<Object, Object> targets = new HashMap<>();
        targets.put(DbKey.PRIMARY, primary);
        targets.putAll(managedReplicaPools);

        CustomRoutingDataSource routingDataSource = new CustomRoutingDataSource();
        routingDataSource.setTargetDataSources(targets);
        routingDataSource.setDefaultTargetDataSource(primary);
        routingDataSource.afterPropertiesSet();
        return routingDataSource;
    }

    private synchronized HikariDataSource getOrCreatePrimaryPool(PersistenceRoutingProperties properties) {
        if (primaryPool == null) {
            primaryPool = buildPool(properties.getPrimary(), false, "hikari-primary");
        }
        return primaryPool;
    }

    private HikariDataSource buildPool(
            PersistenceRoutingProperties.NodeConfig cfg,
            boolean readOnly,
            String poolName) {
        HikariConfig hikari = new HikariConfig();
        hikari.setJdbcUrl(cfg.getUrl());
        hikari.setUsername(cfg.getUsername());
        hikari.setPassword(cfg.getPassword());
        hikari.setMaximumPoolSize(cfg.getMaximumPoolSize());
        hikari.setMinimumIdle(cfg.getMinimumIdle());
        hikari.setConnectionTimeout(cfg.getConnectionTimeoutMs());
        hikari.setValidationTimeout(cfg.getValidationTimeoutMs());
        hikari.setReadOnly(readOnly);
        hikari.setPoolName(poolName);
        return new HikariDataSource(hikari);
    }

    @PreDestroy
    public void closePools() {
        for (HikariDataSource pool : managedReplicaPools.values()) {
            if (!pool.isClosed()) {
                pool.close();
            }
        }
    }
}
