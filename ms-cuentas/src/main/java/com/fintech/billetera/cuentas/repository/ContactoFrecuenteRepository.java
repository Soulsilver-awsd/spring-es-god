package com.fintech.billetera.cuentas.repository;

import com.fintech.billetera.cuentas.domain.ContactoFrecuente;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * Acceso a los contactos frecuentes de una cuenta.
 */
public interface ContactoFrecuenteRepository extends JpaRepository<ContactoFrecuente, Long> {

    List<ContactoFrecuente> findByCuentaPropietarioNumeroCelularOrderByAliasAsc(String numeroCelular);
}
