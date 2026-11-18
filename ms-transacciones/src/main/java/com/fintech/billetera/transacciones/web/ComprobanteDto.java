package com.fintech.billetera.transacciones.web;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

import com.fintech.billetera.transacciones.domain.EstadoTransaccion;
import com.fintech.billetera.transacciones.domain.Transaccion;

/**
 * {@code datos} de una transferencia exitosa ({@code 201 Created}).
 */
public record ComprobanteDto(
        String codigoComprobante,
        String celularOrigen,
        String celularDestino,
        BigDecimal monto,
        String motivo,
        EstadoTransaccion estado,
        BigDecimal nuevoSaldoOrigen,
        OffsetDateTime fechaHora
) {

    public static ComprobanteDto from(Transaccion tx, BigDecimal nuevoSaldoOrigen) {
        return new ComprobanteDto(tx.getCodigoComprobante(), tx.getCelularOrigen(), tx.getCelularDestino(),
                tx.getMonto(), tx.getMotivo(), tx.getEstado(), nuevoSaldoOrigen, tx.getFechaHora());
    }
}
