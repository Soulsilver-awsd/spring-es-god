package com.fintech.billetera.cuentas.service;

import com.fintech.billetera.cuentas.domain.Cuenta;
import com.fintech.billetera.cuentas.domain.EstadoCuenta;
import com.fintech.billetera.cuentas.repository.CuentaRepository;
import com.fintech.billetera.cuentas.web.dto.CrearCuentaRequest;
import com.fintech.billetera.cuentas.web.dto.CuentaDto;
import com.fintech.billetera.cuentas.web.dto.MovimientoInternoRequest;
import com.fintech.billetera.cuentas.web.dto.MovimientoInternoResponse;
import com.fintech.billetera.persistence.annotation.TipoNodo;
import com.fintech.billetera.persistence.annotation.UsarNodo;
import com.fintech.billetera.persistence.audit.DbAuditor;
import com.fintech.billetera.persistence.exception.BusinessConflictException;
import com.fintech.billetera.persistence.exception.BusinessValidationException;
import com.fintech.billetera.persistence.exception.ResourceNotFoundException;
import java.math.BigDecimal;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Escrituras de cuentas: alta de billetera y movimiento interno atomico.
 * Todas las operaciones se ejecutan en el nodo primario.
 */
@Service
public class MovimientoCuentaService {

    private final CuentaRepository cuentaRepository;
    private final DbAuditor dbAuditor;
    private final String instanciaId;

    public MovimientoCuentaService(
            CuentaRepository cuentaRepository,
            DbAuditor dbAuditor,
            @Value("${app.instance-id}") String instanciaId) {
        this.cuentaRepository = cuentaRepository;
        this.dbAuditor = dbAuditor;
        this.instanciaId = instanciaId;
    }

    @UsarNodo(value = TipoNodo.PRIMARY, escritura = true)
    @Transactional
    public OperacionResultado<CuentaDto> crearCuenta(CrearCuentaRequest request) {
        if (cuentaRepository.existsByNumeroCelular(request.numeroCelular())) {
            throw new BusinessConflictException("El numero de celular ya esta registrado: " + request.numeroCelular());
        }
        Cuenta cuenta = new Cuenta(
                request.numeroCelular(),
                request.titular(),
                request.saldo(),
                request.limiteDiario()
        );
        Cuenta guardada = cuentaRepository.save(cuenta);
        return new OperacionResultado<>(toDto(guardada), dbAuditor.capturarAuditoriaActual());
    }

    @UsarNodo(value = TipoNodo.PRIMARY, escritura = true)
    @Transactional
    public OperacionResultado<MovimientoInternoResponse> ejecutarMovimientoInterno(MovimientoInternoRequest request) {
        validarRequest(request);

        // Orden lexicografico fijo para prevenir deadlocks en transferencias cruzadas.
        String primero = request.celularOrigen().compareTo(request.celularDestino()) < 0
                ? request.celularOrigen()
                : request.celularDestino();
        String segundo = primero.equals(request.celularOrigen())
                ? request.celularDestino()
                : request.celularOrigen();

        Cuenta cuentaPrimero = cuentaRepository.findByNumeroCelularForUpdate(primero)
                .orElseThrow(() -> new ResourceNotFoundException("Cuenta no encontrada: " + primero));
        Cuenta cuentaSegundo = cuentaRepository.findByNumeroCelularForUpdate(segundo)
                .orElseThrow(() -> new ResourceNotFoundException("Cuenta no encontrada: " + segundo));

        Cuenta origen = cuentaPrimero.getNumeroCelular().equals(request.celularOrigen())
                ? cuentaPrimero
                : cuentaSegundo;
        Cuenta destino = origen == cuentaPrimero ? cuentaSegundo : cuentaPrimero;

        BigDecimal monto = request.monto().setScale(2, java.math.RoundingMode.HALF_UP);
        validarCuentasActivas(origen, destino);
        validarSaldoYCupo(origen, monto);

        origen.setSaldo(origen.getSaldo().subtract(monto));
        origen.setConsumidoHoy(origen.getConsumidoHoy().add(monto));
        destino.setSaldo(destino.getSaldo().add(monto));

        MovimientoInternoResponse response = new MovimientoInternoResponse(
                origen.getNumeroCelular(),
                destino.getNumeroCelular(),
                monto,
                origen.getSaldo(),
                destino.getSaldo(),
                instanciaId
        );
        return new OperacionResultado<>(response, dbAuditor.capturarAuditoriaActual());
    }

    private void validarRequest(MovimientoInternoRequest request) {
        if (request.monto() == null || request.monto().compareTo(BigDecimal.ZERO) <= 0) {
            throw new BusinessValidationException("El monto debe ser mayor que cero");
        }
        if (request.celularOrigen().equals(request.celularDestino())) {
            throw new BusinessValidationException("La cuenta origen y destino deben ser distintas");
        }
    }

    private void validarCuentasActivas(Cuenta origen, Cuenta destino) {
        if (origen.getEstado() != EstadoCuenta.ACTIVA || destino.getEstado() != EstadoCuenta.ACTIVA) {
            throw new BusinessConflictException("Cuenta bloqueada para transferencias");
        }
    }

    private void validarSaldoYCupo(Cuenta origen, BigDecimal monto) {
        if (origen.getSaldo().compareTo(monto) < 0) {
            throw new BusinessConflictException("Saldo insuficiente");
        }
        BigDecimal nuevoConsumido = origen.getConsumidoHoy().add(monto);
        if (nuevoConsumido.compareTo(origen.getLimiteDiario()) > 0) {
            throw new BusinessConflictException("Limite diario excedido");
        }
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
