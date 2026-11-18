package com.fintech.billetera.transacciones.service;

import java.time.Clock;
import java.time.Year;

import org.springframework.stereotype.Component;

import com.fintech.billetera.transacciones.repository.TransaccionRepository;

/**
 * Genera codigos {@code TX-<anio>-<consecutivo>} (ej. {@code TX-2026-0041}) a partir de la secuencia
 * {@code tx_db.seq_codigo_comprobante}: unicos aunque existan varias instancias concurrentes.
 */
@Component
public class CodigoComprobanteGenerator {

    private final TransaccionRepository repository;
    private final Clock clock;

    public CodigoComprobanteGenerator(TransaccionRepository repository, Clock clock) {
        this.repository = repository;
        this.clock = clock;
    }

    /** Debe invocarse con el contexto de enrutamiento en {@code PRIMARY}. */
    public String siguiente() {
        return "TX-%d-%04d".formatted(Year.now(clock).getValue(), repository.siguienteNumeroComprobante());
    }
}
