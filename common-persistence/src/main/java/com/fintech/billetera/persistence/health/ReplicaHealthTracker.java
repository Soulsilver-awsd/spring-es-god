package com.fintech.billetera.persistence.health;

import com.fintech.billetera.persistence.audit.DbEstadoResponse;
import com.fintech.billetera.persistence.audit.ReplicaEstadoItem;
import com.fintech.billetera.persistence.routing.DbKey;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import javax.sql.DataSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;

/**
 * Supervisa la disponibilidad real de las replicas PostgreSQL en modo Hot Standby,
 * coordina la seleccion Round-Robin y controla la reincorporacion segura tras 2 sondeos exitosos.
 */
public class ReplicaHealthTracker {

    private static final Logger log = LoggerFactory.getLogger(ReplicaHealthTracker.class);
    private static final String HEALTH_QUERY =
            "SELECT pg_is_in_recovery(), COALESCE(pg_last_wal_replay_lsn()::text, 'none')";
    private static final List<DbKey> ORDERED_REPLICAS = List.of(DbKey.REPLICA_1, DbKey.REPLICA_2);

    private final Map<DbKey, DataSource> replicaDataSources;
    private final Map<DbKey, ReplicaStatus> statuses;
    private final AtomicInteger roundRobinCounter = new AtomicInteger(0);
    private final AtomicLong primaryServedQueries = new AtomicLong(0);
    private final int recoverySuccessThreshold;
    private final int queryTimeoutSeconds;

    public ReplicaHealthTracker(
            Map<DbKey, DataSource> replicaDataSources,
            int recoverySuccessThreshold,
            int queryTimeoutSeconds) {
        this.replicaDataSources = new EnumMap<>(replicaDataSources);
        this.recoverySuccessThreshold = recoverySuccessThreshold;
        this.queryTimeoutSeconds = queryTimeoutSeconds;
        this.statuses = new EnumMap<>(DbKey.class);
        for (DbKey key : ORDERED_REPLICAS) {
            if (this.replicaDataSources.containsKey(key)) {
                this.statuses.put(key, new ReplicaStatus(key, true));
            }
        }
    }

    public Optional<DbKey> selectNextHealthyReplica() {
        List<DbKey> healthy = ORDERED_REPLICAS.stream()
                .filter(k -> statuses.containsKey(k) && statuses.get(k).isAvailable())
                .toList();
        if (healthy.isEmpty()) {
            return Optional.empty();
        }
        int idx = Math.floorMod(roundRobinCounter.getAndIncrement(), healthy.size());
        return Optional.of(healthy.get(idx));
    }

    public Optional<DbKey> selectAlternativeHealthyReplica(DbKey failedKey) {
        return ORDERED_REPLICAS.stream()
                .filter(k -> k != failedKey && statuses.containsKey(k) && statuses.get(k).isAvailable())
                .findFirst();
    }

    public void markUnhealthy(DbKey key, String reason) {
        ReplicaStatus status = statuses.get(key);
        if (status == null) {
            return;
        }
        boolean wasAvailable = status.isAvailable();
        status.setAvailable(false);
        status.setConsecutiveSuccesses(0);
        status.setConsecutiveFailures(status.getConsecutiveFailures() + 1);
        status.setLastError(reason);
        status.setLastCheckedAt(Instant.now());
        if (wasAvailable) {
            log.warn("Replica {} marcada como NO disponible: {}", key, reason);
        }
    }

    public void recordQuery(DbKey key) {
        if (key == DbKey.PRIMARY) {
            primaryServedQueries.incrementAndGet();
            return;
        }
        ReplicaStatus status = statuses.get(key);
        if (status != null) {
            status.incrementServedQueries();
        }
    }

    @Scheduled(fixedDelayString = "${app.db.health-check-interval-ms:3000}")
    public void probeReplicas() {
        for (DbKey key : ORDERED_REPLICAS) {
            DataSource ds = replicaDataSources.get(key);
            if (ds != null) {
                probeSingleReplica(key, ds);
            }
        }
    }

    void probeSingleReplica(DbKey key, DataSource ds) {
        ReplicaStatus status = statuses.get(key);
        if (status == null) {
            return;
        }
        try (Connection conn = ds.getConnection();
             PreparedStatement ps = conn.prepareStatement(HEALTH_QUERY)) {
            ps.setQueryTimeout(queryTimeoutSeconds);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    boolean inRecovery = rs.getBoolean(1);
                    String lsn = rs.getString(2);
                    status.setLastCheckedAt(Instant.now());
                    if (inRecovery) {
                        int successes = status.getConsecutiveSuccesses() + 1;
                        status.setConsecutiveSuccesses(successes);
                        status.setConsecutiveFailures(0);
                        status.setLastReplayLsn(lsn);
                        status.setLastError(null);
                        if (!status.isAvailable() && successes >= recoverySuccessThreshold) {
                            status.setAvailable(true);
                            log.info("Replica {} reincorporada tras {} sondeos exitosos (LSN={})",
                                    key, successes, lsn);
                        }
                    } else {
                        markUnhealthy(key, "pg_is_in_recovery() devolvio false");
                    }
                }
            }
        } catch (SQLException ex) {
            markUnhealthy(key, ex.getMessage());
        }
    }

    public DbEstadoResponse getSnapshot(String servicio) {
        Map<String, Long> consultasTotales = Map.of(
                DbKey.PRIMARY.name(), primaryServedQueries.get(),
                DbKey.REPLICA_1.name(), statuses.containsKey(DbKey.REPLICA_1)
                        ? statuses.get(DbKey.REPLICA_1).getServedQueries() : 0L,
                DbKey.REPLICA_2.name(), statuses.containsKey(DbKey.REPLICA_2)
                        ? statuses.get(DbKey.REPLICA_2).getServedQueries() : 0L
        );

        List<ReplicaEstadoItem> items = ORDERED_REPLICAS.stream()
                .filter(statuses::containsKey)
                .map(k -> {
                    ReplicaStatus s = statuses.get(k);
                    return new ReplicaEstadoItem(
                            s.getNodo().name(),
                            s.isAvailable(),
                            s.getConsecutiveSuccesses(),
                            s.getLastReplayLsn(),
                            s.getLastError(),
                            s.getLastCheckedAt()
                    );
                })
                .toList();

        return new DbEstadoResponse(servicio, consultasTotales, items);
    }

    public boolean isHealthy(DbKey key) {
        ReplicaStatus status = statuses.get(key);
        return status != null && status.isAvailable();
    }
}
