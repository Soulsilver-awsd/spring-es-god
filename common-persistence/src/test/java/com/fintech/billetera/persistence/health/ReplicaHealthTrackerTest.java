package com.fintech.billetera.persistence.health;

import com.fintech.billetera.persistence.audit.DbEstadoResponse;
import com.fintech.billetera.persistence.routing.DbKey;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Map;
import java.util.Optional;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ReplicaHealthTrackerTest {

    @Test
    void roundRobinAlternatesBetweenHealthyReplicas() {
        DataSource r1 = mock(DataSource.class);
        DataSource r2 = mock(DataSource.class);
        ReplicaHealthTracker tracker = new ReplicaHealthTracker(
                Map.of(DbKey.REPLICA_1, r1, DbKey.REPLICA_2, r2),
                2,
                2
        );

        assertThat(tracker.selectNextHealthyReplica()).contains(DbKey.REPLICA_1);
        assertThat(tracker.selectNextHealthyReplica()).contains(DbKey.REPLICA_2);
        assertThat(tracker.selectNextHealthyReplica()).contains(DbKey.REPLICA_1);
        assertThat(tracker.selectNextHealthyReplica()).contains(DbKey.REPLICA_2);
    }

    @Test
    void markUnhealthyExcludesFailedReplicaAndReincorporatesAfterTwoSuccesses() throws Exception {
        DataSource r1 = mock(DataSource.class);
        DataSource r2 = mock(DataSource.class);
        mockHealthyStandby(r1, true, "0/1A00010");
        mockHealthyStandby(r2, true, "0/1A00010");

        ReplicaHealthTracker tracker = new ReplicaHealthTracker(
                Map.of(DbKey.REPLICA_1, r1, DbKey.REPLICA_2, r2),
                2,
                2
        );

        tracker.markUnhealthy(DbKey.REPLICA_1, "Connection refused");
        assertThat(tracker.isHealthy(DbKey.REPLICA_1)).isFalse();
        assertThat(tracker.selectNextHealthyReplica()).contains(DbKey.REPLICA_2);
        assertThat(tracker.selectNextHealthyReplica()).contains(DbKey.REPLICA_2);
        assertThat(tracker.selectAlternativeHealthyReplica(DbKey.REPLICA_1)).contains(DbKey.REPLICA_2);

        // Primer sondeo exitoso: aun en RECOVERING (1/2), no debe reincorporarse
        tracker.probeReplicas();
        assertThat(tracker.isHealthy(DbKey.REPLICA_1)).isFalse();

        // Segundo sondeo consecutivo exitoso: pasa a HEALTHY (2/2)
        tracker.probeReplicas();
        assertThat(tracker.isHealthy(DbKey.REPLICA_1)).isTrue();
    }

    @Test
    void failedProbeResetsConsecutiveSuccessesAndReturnsEmptyWhenBothDown() throws Exception {
        DataSource r1 = mock(DataSource.class);
        DataSource r2 = mock(DataSource.class);
        when(r1.getConnection()).thenThrow(new SQLException("timeout"));
        when(r2.getConnection()).thenThrow(new SQLException("timeout"));

        ReplicaHealthTracker tracker = new ReplicaHealthTracker(
                Map.of(DbKey.REPLICA_1, r1, DbKey.REPLICA_2, r2),
                2,
                2
        );

        tracker.probeReplicas();
        assertThat(tracker.isHealthy(DbKey.REPLICA_1)).isFalse();
        assertThat(tracker.isHealthy(DbKey.REPLICA_2)).isFalse();
        assertThat(tracker.selectNextHealthyReplica()).isEqualTo(Optional.empty());

        tracker.recordQuery(DbKey.PRIMARY);
        tracker.recordQuery(DbKey.REPLICA_2);
        DbEstadoResponse snapshot = tracker.getSnapshot("ms-cuentas-1:8081");
        assertThat(snapshot.consultasTotales().get("PRIMARY")).isEqualTo(1L);
        assertThat(snapshot.consultasTotales().get("REPLICA_2")).isEqualTo(1L);
    }

    @Test
    void primaryNodeReportingNotInRecoveryIsMarkedUnhealthy() throws Exception {
        DataSource r1 = mock(DataSource.class);
        mockHealthyStandby(r1, false, "none");

        ReplicaHealthTracker tracker = new ReplicaHealthTracker(
                Map.of(DbKey.REPLICA_1, r1),
                2,
                2
        );

        tracker.probeReplicas();
        assertThat(tracker.isHealthy(DbKey.REPLICA_1)).isFalse();
    }

    private void mockHealthyStandby(DataSource ds, boolean inRecovery, String lsn) throws Exception {
        Connection conn = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(ds.getConnection()).thenReturn(conn);
        when(conn.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getBoolean(1)).thenReturn(inRecovery);
        when(rs.getString(2)).thenReturn(lsn);
    }
}
