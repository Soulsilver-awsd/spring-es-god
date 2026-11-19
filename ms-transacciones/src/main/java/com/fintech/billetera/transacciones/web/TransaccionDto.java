package com.fintech.billetera.transacciones.web;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

import com.fintech.billetera.transacciones.domain.EstadoTransaccion;
import com.fintech.billetera.transacciones.domain.Transaccion;

/**
 * Movimiento del libro mayor (historial y comprobante).
 */
public record TransaccionDto(
        String codigoComprobante,
        String celularOrigen,
        String celularDestino,
        BigDecimal monto,
        String motivo,
        EstadoTransaccion estado,
        OffsetDateTime fechaHora
) {

    public static TransaccionDto from(Transaccion tx) {
        return new TransaccionDto(tx.getCodigoComprobante(), tx.getCelularOrigen(), tx.getCelularDestino(),
                tx.getMonto(), tx.getMotivo(), tx.getEstado(), tx.getFechaHora());
    }
}
