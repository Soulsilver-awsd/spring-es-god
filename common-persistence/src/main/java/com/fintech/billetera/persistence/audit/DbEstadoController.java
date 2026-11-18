package com.fintech.billetera.persistence.audit;

import com.fintech.billetera.persistence.health.ReplicaHealthTracker;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Endpoint comun de observabilidad para verificar reparto Round-Robin y estado de replicas.
 */
@RestController
@RequestMapping("/api/db")
public class DbEstadoController {

    private final ReplicaHealthTracker replicaHealthTracker;
    private final DbAuditor dbAuditor;

    public DbEstadoController(ReplicaHealthTracker replicaHealthTracker, DbAuditor dbAuditor) {
        this.replicaHealthTracker = replicaHealthTracker;
        this.dbAuditor = dbAuditor;
    }

    @GetMapping("/estado")
    public DbEstadoResponse obtenerEstado() {
        return replicaHealthTracker.getSnapshot(dbAuditor.getServicioOrigen());
    }
}
