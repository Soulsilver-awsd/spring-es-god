package com.fintech.billetera.persistence.audit;

import com.fintech.billetera.persistence.routing.PoliticaEnrutamiento;

/**
 * Trazabilidad real del microservicio y del nodo PostgreSQL que atendio la operacion.
 */
public record AuditoriaTecnicaDto(
        String servicioOrigen,
        String instanciaCuentasConsultada,
        String nodoBaseDatos,
        PoliticaEnrutamiento politicaEnrutamiento
) {
}
