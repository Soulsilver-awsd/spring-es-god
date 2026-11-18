package com.fintech.billetera.persistence.routing;

import com.fintech.billetera.persistence.annotation.TipoNodo;
import com.fintech.billetera.persistence.annotation.UsarNodo;
import com.fintech.billetera.persistence.health.ReplicaHealthTracker;
import java.util.Map;
import javax.sql.DataSource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.aop.aspectj.annotation.AspectJProxyFactory;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class DbRoutingAspectTest {

    @AfterEach
    void cleanup() {
        RequestContextHolder.resetRequestAttributes();
        DbContextHolder.clear();
    }

    @Test
    void routesWritesCriticalReadsAndRoundRobinReplicasCorrectly() {
        ReplicaHealthTracker tracker = new ReplicaHealthTracker(
                Map.of(DbKey.REPLICA_1, mock(DataSource.class), DbKey.REPLICA_2, mock(DataSource.class)),
                2,
                2
        );
        DummyService proxy = createProxy(new DummyService(), tracker);

        assertThat(proxy.writeOperation()).isEqualTo("PRIMARY:ESCRITURA_DIRECTA:false");
        assertThat(proxy.criticalRead()).isEqualTo("PRIMARY:LECTURA_CRITICA_PRIMARIO:false");
        assertThat(proxy.ordinaryRead()).isEqualTo("REPLICA_1:ROUND_ROBIN_REPLICA:false");
        assertThat(proxy.ordinaryRead()).isEqualTo("REPLICA_2:ROUND_ROBIN_REPLICA:false");
        // ThreadLocal debe quedar limpio al salir del aspecto
        assertThat(DbContextHolder.getDbKey()).isNull();
    }

    @Test
    void criticalConsistencyHeaderForcesPrimaryOnOrdinaryRead() {
        MockHttpServletRequest req = new MockHttpServletRequest();
        req.addHeader(DbRoutingAspect.HEADER_CONSISTENCIA, "CRITICA");
        RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(req));

        ReplicaHealthTracker tracker = new ReplicaHealthTracker(
                Map.of(DbKey.REPLICA_1, mock(DataSource.class), DbKey.REPLICA_2, mock(DataSource.class)),
                2,
                2
        );
        DummyService proxy = createProxy(new DummyService(), tracker);

        assertThat(proxy.ordinaryRead()).isEqualTo("PRIMARY:LECTURA_CRITICA_PRIMARIO:false");
    }

    @Test
    void failoverRescuesReadWhenSelectedReplicaThrowsDataAccessException() {
        ReplicaHealthTracker tracker = new ReplicaHealthTracker(
                Map.of(DbKey.REPLICA_1, mock(DataSource.class), DbKey.REPLICA_2, mock(DataSource.class)),
                2,
                2
        );
        DummyService proxy = createProxy(new DummyService(), tracker);

        String result = proxy.readFailsOnReplica1();
        assertThat(result).isEqualTo("REPLICA_2:FAILOVER_REPLICA:true");
        assertThat(tracker.isHealthy(DbKey.REPLICA_1)).isFalse();
        assertThat(tracker.isHealthy(DbKey.REPLICA_2)).isTrue();
    }

    private DummyService createProxy(DummyService target, ReplicaHealthTracker tracker) {
        AspectJProxyFactory factory = new AspectJProxyFactory(target);
        factory.setProxyTargetClass(true);
        factory.addAspect(new DbRoutingAspect(tracker));
        return factory.getProxy();
    }

    static class DummyService {

        @UsarNodo(value = TipoNodo.PRIMARY, escritura = true)
        public String writeOperation() {
            return snapshot();
        }

        @UsarNodo(TipoNodo.PRIMARY)
        public String criticalRead() {
            return snapshot();
        }

        @UsarNodo(TipoNodo.REPLICA)
        public String ordinaryRead() {
            return snapshot();
        }

        @UsarNodo(TipoNodo.REPLICA)
        public String readFailsOnReplica1() {
            if (DbContextHolder.getDbKey() == DbKey.REPLICA_1) {
                throw new DataAccessResourceFailureException("Simulated replica1 outage");
            }
            return snapshot();
        }

        private String snapshot() {
            return DbContextHolder.getDbKey() + ":" + DbContextHolder.getPolicy()
                    + ":" + DbContextHolder.isFallbackUsed();
        }
    }
}
