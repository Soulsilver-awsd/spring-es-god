package com.fintech.billetera.persistence.routing;

/**
 * Politica aplicada durante el enrutamiento JDBC para trazabilidad en ApiResponse.
 */
public enum PoliticaEnrutamiento {
    ESCRITURA_DIRECTA,
    LECTURA_CRITICA_PRIMARIO,
    ROUND_ROBIN_REPLICA,
    FAILOVER_REPLICA
}
