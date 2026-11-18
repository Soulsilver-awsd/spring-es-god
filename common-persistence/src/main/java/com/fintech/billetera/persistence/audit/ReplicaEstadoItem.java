package com.fintech.billetera.persistence.audit;

import java.time.Instant;

/**
 * Estado individual de una replica PostgreSQL reportado por /api/db/estado.
 */
public record ReplicaEstadoItem(
        String nodo,
        boolean available,
        int consecutiveSuccesses,
        String lastReplayLsn,
        String lastError,
        Instant lastCheckedAt
) {
}
