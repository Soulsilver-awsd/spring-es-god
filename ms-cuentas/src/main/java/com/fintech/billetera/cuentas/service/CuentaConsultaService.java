package com.fintech.billetera.cuentas.service;

import com.fintech.billetera.cuentas.domain.Cuenta;
import com.fintech.billetera.cuentas.repository.ContactoFrecuenteRepository;
import com.fintech.billetera.cuentas.repository.CuentaRepository;
import com.fintech.billetera.cuentas.web.dto.ContactoDto;
import com.fintech.billetera.cuentas.web.dto.CuentaDto;
import com.fintech.billetera.cuentas.web.dto.InstanciaDto;
import com.fintech.billetera.cuentas.web.dto.SaldoCriticoDto;
import com.fintech.billetera.persistence.annotation.TipoNodo;
import com.fintech.billetera.persistence.annotation.UsarNodo;
import com.fintech.billetera.persistence.audit.AuditoriaTecnicaDto;
import com.fintech.billetera.persistence.audit.DbAuditor;
import com.fintech.billetera.persistence.exception.ResourceNotFoundException;
import java.time.Instant;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Consultas de perfil, saldo, contactos y diagnostico.
 * Las lecturas ordinarias van a replicas; el saldo critico va al primario (RYOW).
 */
@Service
public class CuentaConsultaService {

    private final CuentaRepository cuentaRepository;
    private final ContactoFrecuenteRepository contactoFrecuenteRepository;
    private final DbAuditor dbAuditor;
    private final String instanciaId;
    private final int puerto;

    public CuentaConsultaService(
            CuentaRepository cuentaRepository,
            ContactoFrecuenteRepository contactoFrecuenteRepository,
            DbAuditor dbAuditor,
            @Value("${app.instance-id}") String instanciaId,
            @Value("${server.port}") int puerto) {
        this.cuentaRepository = cuentaRepository;
        this.contactoFrecuenteRepository = contactoFrecuenteRepository;
        this.dbAuditor = dbAuditor;
        this.instanciaId = instanciaId;
        this.puerto = puerto;
    }

    @UsarNodo(TipoNodo.REPLICA)
    @Transactional(readOnly = true)
    public OperacionResultado<CuentaDto> obtenerPorCelular(String celular) {
        Cuenta cuenta = cuentaRepository.findByNumeroCelular(celular)
                .orElseThrow(() -> new ResourceNotFoundException("Cuenta no encontrada: " + celular));
        return new OperacionResultado<>(toDto(cuenta), dbAuditor.capturarAuditoriaActual());
    }

    @UsarNodo(TipoNodo.REPLICA)
    @Transactional(readOnly = true)
    public OperacionResultado<List<ContactoDto>> obtenerContactos(String celular) {
        if (!cuentaRepository.existsByNumeroCelular(celular)) {
            throw new ResourceNotFoundException("Cuenta no encontrada: " + celular);
        }
        List<ContactoDto> contactos = contactoFrecuenteRepository
                .findByCuentaPropietarioNumeroCelularOrderByAliasAsc(celular)
                .stream()
                .map(c -> new ContactoDto(c.getCelularContacto(), c.getAlias()))
                .toList();
        return new OperacionResultado<>(contactos, dbAuditor.capturarAuditoriaActual());
    }

    @UsarNodo(TipoNodo.PRIMARY)
    @Transactional(readOnly = true)
    public OperacionResultado<SaldoCriticoDto> obtenerSaldoCritico(String celular) {
        Cuenta cuenta = cuentaRepository.findByNumeroCelular(celular)
                .orElseThrow(() -> new ResourceNotFoundException("Cuenta no encontrada: " + celular));
        SaldoCriticoDto dto = new SaldoCriticoDto(
                cuenta.getNumeroCelular(),
                cuenta.getSaldo(),
                cuenta.getLimiteDiario(),
                cuenta.getConsumidoHoy(),
                Instant.now()
        );
        return new OperacionResultado<>(dto, dbAuditor.capturarAuditoriaActual());
    }

    @UsarNodo(TipoNodo.REPLICA)
    @Transactional(readOnly = true)
    public OperacionResultado<InstanciaDto> obtenerDiagnosticoInstancia() {
        // La consulta de auditoria fuerza una lectura real sobre el nodo seleccionado.
        AuditoriaTecnicaDto auditoria = dbAuditor.capturarAuditoriaActual();
        InstanciaDto dto = new InstanciaDto(instanciaId, puerto, Instant.now());
        return new OperacionResultado<>(dto, auditoria);
    }

    private CuentaDto toDto(Cuenta cuenta) {
        return new CuentaDto(
                cuenta.getNumeroCelular(),
                cuenta.getTitular(),
                cuenta.getSaldo(),
                cuenta.getLimiteDiario(),
                cuenta.getConsumidoHoy(),
                cuenta.getEstado()
        );
    }
}
