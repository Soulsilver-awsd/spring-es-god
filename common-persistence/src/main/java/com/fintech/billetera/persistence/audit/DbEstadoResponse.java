package com.fintech.billetera.persistence.audit;

import java.util.List;
import java.util.Map;

/**
 * Respuesta de diagnostico de observabilidad en tiempo real (/api/db/estado).
 */
public record DbEstadoResponse(
        String servicio,
        Map<String, Long> consultasTotales,
        List<ReplicaEstadoItem> replicas
) {
}
