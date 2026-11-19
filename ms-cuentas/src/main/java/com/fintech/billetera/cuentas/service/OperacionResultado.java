package com.fintech.billetera.cuentas.service;

import com.fintech.billetera.persistence.audit.AuditoriaTecnicaDto;

/**
 * Resultado interno que transporta los datos de negocio junto con la auditoria
 * capturada dentro del mismo contexto de enrutamiento JDBC.
 */
public record OperacionResultado<T>(T datos, AuditoriaTecnicaDto auditoria) {
}
