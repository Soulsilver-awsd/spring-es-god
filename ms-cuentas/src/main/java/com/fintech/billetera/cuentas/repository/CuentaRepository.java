package com.fintech.billetera.cuentas.repository;

import com.fintech.billetera.cuentas.domain.Cuenta;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * Acceso a cuentas. Las escrituras usan bloqueo pesimista para movimientos atomicos.
 */
public interface CuentaRepository extends JpaRepository<Cuenta, Long> {

    Optional<Cuenta> findByNumeroCelular(String numeroCelular);

    boolean existsByNumeroCelular(String numeroCelular);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT c FROM Cuenta c WHERE c.numeroCelular = :celular")
    Optional<Cuenta> findByNumeroCelularForUpdate(@Param("celular") String celular);
}
