package com.fintech.billetera.transacciones.service;

import com.fintech.billetera.persistence.audit.AuditoriaTecnicaDto;

/**
 * Resultado de un servicio {@code @UsarNodo} con la auditoria capturada <b>dentro</b> del contexto
 * de enrutamiento (el aspecto lo limpia al salir, antes de que el controlador arme la respuesta).
 */
public record ResultadoOperacion<T>(T datos, AuditoriaTecnicaDto auditoria) {
}
