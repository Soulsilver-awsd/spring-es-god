package com.fintech.billetera.transacciones.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Service;

import com.fintech.billetera.persistence.annotation.TipoNodo;
import com.fintech.billetera.persistence.annotation.UsarNodo;
import com.fintech.billetera.persistence.audit.AuditoriaTecnicaDto;
import com.fintech.billetera.persistence.audit.DbAuditor;
import com.fintech.billetera.persistence.exception.BusinessValidationException;
import com.fintech.billetera.transacciones.client.CuentasHttpClient;
import com.fintech.billetera.transacciones.client.CuentasRechazoException;
import com.fintech.billetera.transacciones.client.ResultadoMovimiento;
import com.fintech.billetera.transacciones.domain.EstadoTransaccion;
import com.fintech.billetera.transacciones.domain.Transaccion;
import com.fintech.billetera.transacciones.repository.TransaccionRepository;
import com.fintech.billetera.transacciones.web.ComprobanteDto;
import com.fintech.billetera.transacciones.web.TransferenciaRequest;

/**
 * Orquesta la transferencia P2P (RF-06, SDD 04 seccion 3; ADR-006).
 *
 * <p><b>Transaccionalidad:</b> el metodo no es {@code @Transactional} a proposito. La llamada a
 * ms-cuentas (hasta 5 s) ocurre fuera de cualquier transaccion para no retener una conexion del
 * primario, y cada escritura en {@code tx_db} (consecutivo y registro) es una transaccion corta e
 * independiente. Asi el registro {@code RECHAZADA} se confirma aunque luego se lance el error de
 * negocio, sin necesidad de {@code REQUIRES_NEW} ni de invocaciones {@code @UsarNodo} anidadas.</p>
 *
 * <p><b>Riesgo residual (ADR-006):</b> si ms-cuentas aplica el movimiento y luego falla el
 * {@code INSERT} del comprobante, el saldo queda movido sin registro; se deja traza {@code ERROR}
 * con todos los datos para conciliacion manual.</p>
 */
@Service
public class TransferenciaOrchestratorService {

    private static final Logger log = LoggerFactory.getLogger(TransferenciaOrchestratorService.class);

    private final CuentasHttpClient cuentasHttpClient;
    private final TransaccionRepository repository;
    private final CodigoComprobanteGenerator codigoGenerator;
    private final DbAuditor dbAuditor;
    private final Clock clock;

    public TransferenciaOrchestratorService(CuentasHttpClient cuentasHttpClient, TransaccionRepository repository,
                                            CodigoComprobanteGenerator codigoGenerator, DbAuditor dbAuditor,
                                            Clock clock) {
        this.cuentasHttpClient = cuentasHttpClient;
        this.repository = repository;
        this.codigoGenerator = codigoGenerator;
        this.dbAuditor = dbAuditor;
        this.clock = clock;
    }

    @UsarNodo(value = TipoNodo.PRIMARY, escritura = true)
    public ResultadoOperacion<ComprobanteDto> transferir(TransferenciaRequest request) {
        if (request.celularOrigen().equals(request.celularDestino())) {
            throw new BusinessValidationException("Cuenta origen y destino deben ser distintas");
        }
        BigDecimal monto = request.monto().setScale(2, RoundingMode.UNNECESSARY);

        ResultadoMovimiento movimiento;
        try {
            movimiento = cuentasHttpClient.ejecutarMovimiento(request.celularOrigen(), request.celularDestino(), monto);
        } catch (CuentasRechazoException rechazo) {
            registrarRechazo(request, monto, rechazo);
            throw new OperacionRechazadaException(rechazo.getStatus(), rechazo.getMessage(),
                    auditoria(rechazo.getInstanciaCuentas()));
        }

        // El consecutivo se asigna solo cuando ms-cuentas respondio: un 503 no consume numeros.
        String codigo = null;
        Transaccion exitosa;
        try {
            codigo = codigoGenerator.siguiente();
            exitosa = repository.save(nueva(codigo, request, monto, EstadoTransaccion.EXITOSA));
        } catch (DataAccessException ex) {
            log.error("CONCILIACION REQUERIDA: ms-cuentas ({}) aplico {} de {} a {} pero no se pudo registrar {}",
                    movimiento.instanciaAtendio(), monto, request.celularOrigen(),
                    request.celularDestino(), codigo, ex);
            throw ex;
        }
        log.info("Transferencia {} EXITOSA ({} -> {}, {}) via {}", codigo, request.celularOrigen(),
                request.celularDestino(), monto, movimiento.instanciaAtendio());

        return new ResultadoOperacion<>(
                ComprobanteDto.from(exitosa, movimiento.movimiento().nuevoSaldoOrigen()),
                auditoria(movimiento.instanciaAtendio()));
    }

    private void registrarRechazo(TransferenciaRequest request, BigDecimal monto, CuentasRechazoException rechazo) {
        String codigo = null;
        try {
            codigo = codigoGenerator.siguiente();
            repository.save(nueva(codigo, request, monto, EstadoTransaccion.RECHAZADA));
            log.info("Transferencia {} RECHAZADA por ms-cuentas ({}): {}", codigo, rechazo.getStatus().value(),
                    rechazo.getMessage());
        } catch (DataAccessException ex) {
            // El rechazo de negocio sigue siendo la respuesta correcta; solo se pierde la traza del intento.
            log.warn("No se pudo registrar el rechazo {} ({} -> {}): {}", codigo, request.celularOrigen(),
                    request.celularDestino(), ex.getMessage());
        }
    }

    private Transaccion nueva(String codigo, TransferenciaRequest request, BigDecimal monto,
                              EstadoTransaccion estado) {
        // Precision de microsegundos, igual que TIMESTAMPTZ: el comprobante consultado luego coincide.
        OffsetDateTime ahora = OffsetDateTime.now(clock).truncatedTo(ChronoUnit.MICROS);
        return new Transaccion(codigo, request.celularOrigen(), request.celularDestino(), monto,
                request.motivo(), estado, ahora);
    }

    private AuditoriaTecnicaDto auditoria(String instanciaCuentas) {
        try {
            return dbAuditor.capturarAuditoriaActual(instanciaCuentas);
        } catch (DataAccessException ex) {
            log.warn("No se pudo capturar la auditoria del nodo: {}", ex.getMessage());
            return dbAuditor.auditoriaSinConsultaSql(instanciaCuentas);
        }
    }
}
