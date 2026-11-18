package com.fintech.billetera.transacciones.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.transaction.annotation.Transactional;

import com.fintech.billetera.transacciones.domain.Transaccion;

public interface TransaccionRepository extends JpaRepository<Transaccion, Long> {

    /** Movimientos donde el celular participa como origen o destino, del mas reciente al mas antiguo. */
    List<Transaccion> findByCelularOrigenOrCelularDestinoOrderByFechaHoraDesc(String origen, String destino);

    Optional<Transaccion> findByCodigoComprobante(String codigoComprobante);

    /**
     * Siguiente consecutivo de comprobante. Requiere transaccion de escritura: PostgreSQL rechaza
     * {@code nextval()} dentro de una transaccion {@code READ ONLY} (los metodos de consulta de
     * Spring Data son {@code readOnly} por defecto).
     */
    @Transactional
    @Query(value = "SELECT nextval('tx_db.seq_codigo_comprobante')", nativeQuery = true)
    long siguienteNumeroComprobante();
}
