package com.fintech.billetera.transacciones.service;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.fintech.billetera.persistence.annotation.TipoNodo;
import com.fintech.billetera.persistence.annotation.UsarNodo;
import com.fintech.billetera.persistence.audit.DbAuditor;
import com.fintech.billetera.transacciones.repository.TransaccionRepository;
import com.fintech.billetera.transacciones.web.TransaccionDto;

/**
 * Consultas del libro mayor (RF-07, RF-08). La auditoria se captura dentro de la misma transaccion,
 * por lo que reporta la conexion JDBC real que sirvio los datos.
 */
@Service
public class TransaccionConsultaService {

    private final TransaccionRepository repository;
    private final DbAuditor dbAuditor;

    public TransaccionConsultaService(TransaccionRepository repository, DbAuditor dbAuditor) {
        this.repository = repository;
        this.dbAuditor = dbAuditor;
    }

    /** Lectura ordinaria en replicas (Round-Robin); tolera el lag WAL breve. */
    @UsarNodo(TipoNodo.REPLICA)
    @Transactional(readOnly = true)
    public ResultadoOperacion<List<TransaccionDto>> listarHistorial(String celular) {
        List<TransaccionDto> historial = repository
                .findByCelularOrigenOrCelularDestinoOrderByFechaHoraDesc(celular, celular)
                .stream()
                .map(TransaccionDto::from)
                .toList();
        return new ResultadoOperacion<>(historial, dbAuditor.capturarAuditoriaActual());
    }

    /** Lectura critica RYOW en el primario: el comprobante recien emitido es visible de inmediato. */
    @UsarNodo(TipoNodo.PRIMARY)
    @Transactional(readOnly = true)
    public ResultadoOperacion<TransaccionDto> consultarComprobanteCritico(String codigo) {
        return repository.findByCodigoComprobante(codigo)
                .map(tx -> new ResultadoOperacion<>(TransaccionDto.from(tx), dbAuditor.capturarAuditoriaActual()))
                .orElseThrow(() -> new OperacionRechazadaException(HttpStatus.NOT_FOUND,
                        "Comprobante " + codigo + " no existe", dbAuditor.capturarAuditoriaActual()));
    }
}
