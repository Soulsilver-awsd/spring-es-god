package com.fintech.billetera.cuentas.service;

import com.fintech.billetera.cuentas.domain.Cuenta;
import com.fintech.billetera.cuentas.domain.EstadoCuenta;
import com.fintech.billetera.cuentas.repository.CuentaRepository;
import com.fintech.billetera.cuentas.web.dto.CrearCuentaRequest;
import com.fintech.billetera.cuentas.web.dto.CuentaDto;
import com.fintech.billetera.cuentas.web.dto.MovimientoInternoRequest;
import com.fintech.billetera.cuentas.web.dto.MovimientoInternoResponse;
import com.fintech.billetera.persistence.audit.AuditoriaTecnicaDto;
import com.fintech.billetera.persistence.audit.DbAuditor;
import com.fintech.billetera.persistence.exception.BusinessConflictException;
import com.fintech.billetera.persistence.exception.BusinessValidationException;
import com.fintech.billetera.persistence.exception.ResourceNotFoundException;
import com.fintech.billetera.persistence.routing.PoliticaEnrutamiento;
import java.math.BigDecimal;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class MovimientoCuentaServiceTest {

    private static final String INSTANCIA = "ms-cuentas-1:8081";
    private static final AuditoriaTecnicaDto AUDITORIA = new AuditoriaTecnicaDto(
            INSTANCIA, null, "PRIMARY (172.19.0.2:5432, recovery=false)",
            PoliticaEnrutamiento.ESCRITURA_DIRECTA);

    @Mock
    private CuentaRepository cuentaRepository;

    @Mock
    private DbAuditor dbAuditor;

    private MovimientoCuentaService service;

    @BeforeEach
    void setUp() {
        service = new MovimientoCuentaService(cuentaRepository, dbAuditor, INSTANCIA);
    }

    private Cuenta cuenta(String celular, String titular, String saldo, String limite) {
        return new Cuenta(celular, titular, new BigDecimal(saldo), new BigDecimal(limite));
    }

    private MovimientoInternoRequest movimiento(String origen, String destino, String monto) {
        return new MovimientoInternoRequest(origen, destino, new BigDecimal(monto));
    }

    // ------------------------------------------------------------------ alta

    @Test
    void crearCuentaPersisteCuandoElCelularNoExiste() {
        CrearCuentaRequest request = new CrearCuentaRequest(
                "0951234567", "Mario Ruiz", new BigDecimal("250.00"), new BigDecimal("150.00"));
        when(cuentaRepository.existsByNumeroCelular("0951234567")).thenReturn(false);
        when(cuentaRepository.save(any(Cuenta.class))).thenAnswer(inv -> inv.getArgument(0));
        when(dbAuditor.capturarAuditoriaActual()).thenReturn(AUDITORIA);

        OperacionResultado<CuentaDto> resultado = service.crearCuenta(request);

        assertThat(resultado.auditoria()).isEqualTo(AUDITORIA);
        assertThat(resultado.datos().numeroCelular()).isEqualTo("0951234567");
        assertThat(resultado.datos().titular()).isEqualTo("Mario Ruiz");
        assertThat(resultado.datos().saldo()).isEqualByComparingTo("250.00");
        assertThat(resultado.datos().consumidoHoy()).isEqualByComparingTo("0.00");
    }

    @Test
    void crearCuentaRechazaCelularDuplicado() {
        CrearCuentaRequest request = new CrearCuentaRequest(
                "0951234567", "Mario Ruiz", new BigDecimal("250.00"), new BigDecimal("150.00"));
        when(cuentaRepository.existsByNumeroCelular("0951234567")).thenReturn(true);

        assertThatThrownBy(() -> service.crearCuenta(request))
                .isInstanceOf(BusinessConflictException.class)
                .hasMessageContaining("ya esta registrado");
    }

    // -------------------------------------------------------------- movimiento

    @Test
    void movimientoFelizActualizaSaldosYConsumido() {
        Cuenta origen = cuenta("0991112233", "Ana Torres", "500.00", "300.00");
        Cuenta destino = cuenta("0984445566", "Luis Mendez", "150.00", "500.00");
        when(cuentaRepository.findByNumeroCelularForUpdate("0984445566")).thenReturn(Optional.of(destino));
        when(cuentaRepository.findByNumeroCelularForUpdate("0991112233")).thenReturn(Optional.of(origen));
        when(dbAuditor.capturarAuditoriaActual()).thenReturn(AUDITORIA);

        OperacionResultado<MovimientoInternoResponse> resultado = service.ejecutarMovimientoInterno(
                movimiento("0991112233", "0984445566", "25.00"));

        assertThat(origen.getSaldo()).isEqualByComparingTo("475.00");
        assertThat(origen.getConsumidoHoy()).isEqualByComparingTo("25.00");
        assertThat(destino.getSaldo()).isEqualByComparingTo("175.00");
        assertThat(resultado.auditoria()).isEqualTo(AUDITORIA);
        assertThat(resultado.datos().nuevoSaldoOrigen()).isEqualByComparingTo("475.00");
        assertThat(resultado.datos().nuevoSaldoDestino()).isEqualByComparingTo("175.00");
        assertThat(resultado.datos().instanciaAtendio()).isEqualTo(INSTANCIA);
    }

    @Test
    void bloqueaEnOrdenLexicograficoCuandoOrigenEsMayor() {
        Cuenta a = cuenta("0984445566", "Luis Mendez", "150.00", "500.00");
        Cuenta b = cuenta("0991112233", "Ana Torres", "500.00", "300.00");
        when(cuentaRepository.findByNumeroCelularForUpdate("0984445566")).thenReturn(Optional.of(a));
        when(cuentaRepository.findByNumeroCelularForUpdate("0991112233")).thenReturn(Optional.of(b));
        when(dbAuditor.capturarAuditoriaActual()).thenReturn(AUDITORIA);

        service.ejecutarMovimientoInterno(movimiento("0991112233", "0984445566", "10.00"));

        InOrder orden = inOrder(cuentaRepository);
        orden.verify(cuentaRepository).findByNumeroCelularForUpdate("0984445566");
        orden.verify(cuentaRepository).findByNumeroCelularForUpdate("0991112233");
    }

    @Test
    void bloqueaEnElMismoOrdenCuandoOrigenEsMenor() {
        Cuenta a = cuenta("0984445566", "Luis Mendez", "150.00", "500.00");
        Cuenta b = cuenta("0991112233", "Ana Torres", "500.00", "300.00");
        when(cuentaRepository.findByNumeroCelularForUpdate("0984445566")).thenReturn(Optional.of(a));
        when(cuentaRepository.findByNumeroCelularForUpdate("0991112233")).thenReturn(Optional.of(b));
        when(dbAuditor.capturarAuditoriaActual()).thenReturn(AUDITORIA);

        service.ejecutarMovimientoInterno(movimiento("0984445566", "0991112233", "10.00"));

        InOrder orden = inOrder(cuentaRepository);
        orden.verify(cuentaRepository).findByNumeroCelularForUpdate("0984445566");
        orden.verify(cuentaRepository).findByNumeroCelularForUpdate("0991112233");
    }

    // ------------------------------------------------------------- validaciones

    @Test
    void rechazaMontoNuloOCeroONegativo() {
        assertThatThrownBy(() -> service.ejecutarMovimientoInterno(
                new MovimientoInternoRequest("0991112233", "0984445566", null)))
                .isInstanceOf(BusinessValidationException.class);

        assertThatThrownBy(() -> service.ejecutarMovimientoInterno(
                movimiento("0991112233", "0984445566", "0.00")))
                .isInstanceOf(BusinessValidationException.class);

        assertThatThrownBy(() -> service.ejecutarMovimientoInterno(
                movimiento("0991112233", "0984445566", "-1.00")))
                .isInstanceOf(BusinessValidationException.class);
    }

    @Test
    void rechazaMismoCelularOrigenYDestino() {
        assertThatThrownBy(() -> service.ejecutarMovimientoInterno(
                movimiento("0991112233", "0991112233", "10.00")))
                .isInstanceOf(BusinessValidationException.class)
                .hasMessageContaining("distintas");
    }

    @Test
    void rechazaCuentaInexistente() {
        when(cuentaRepository.findByNumeroCelularForUpdate("0984445566")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.ejecutarMovimientoInterno(
                movimiento("0991112233", "0984445566", "10.00")))
                .isInstanceOf(ResourceNotFoundException.class);
    }

    @Test
    void rechazaCuentaBloqueadaSinMutarSaldos() {
        Cuenta origen = cuenta("0991112233", "Ana Torres", "500.00", "300.00");
        origen.setEstado(EstadoCuenta.BLOQUEADA);
        Cuenta destino = cuenta("0984445566", "Luis Mendez", "150.00", "500.00");
        when(cuentaRepository.findByNumeroCelularForUpdate("0984445566")).thenReturn(Optional.of(destino));
        when(cuentaRepository.findByNumeroCelularForUpdate("0991112233")).thenReturn(Optional.of(origen));

        assertThatThrownBy(() -> service.ejecutarMovimientoInterno(
                movimiento("0991112233", "0984445566", "10.00")))
                .isInstanceOf(BusinessConflictException.class)
                .hasMessageContaining("bloqueada");

        assertThat(origen.getSaldo()).isEqualByComparingTo("500.00");
        assertThat(destino.getSaldo()).isEqualByComparingTo("150.00");
    }

    @Test
    void rechazaSaldoInsuficienteSinMutarSaldos() {
        Cuenta origen = cuenta("0991112233", "Ana Torres", "10.00", "300.00");
        Cuenta destino = cuenta("0984445566", "Luis Mendez", "150.00", "500.00");
        when(cuentaRepository.findByNumeroCelularForUpdate("0984445566")).thenReturn(Optional.of(destino));
        when(cuentaRepository.findByNumeroCelularForUpdate("0991112233")).thenReturn(Optional.of(origen));

        assertThatThrownBy(() -> service.ejecutarMovimientoInterno(
                movimiento("0991112233", "0984445566", "25.00")))
                .isInstanceOf(BusinessConflictException.class)
                .hasMessageContaining("Saldo insuficiente");

        assertThat(origen.getSaldo()).isEqualByComparingTo("10.00");
        assertThat(destino.getSaldo()).isEqualByComparingTo("150.00");
    }

    @Test
    void rechazaLimiteDiarioExcedidoSinMutarSaldos() {
        Cuenta origen = cuenta("0991112233", "Ana Torres", "500.00", "300.00");
        origen.setConsumidoHoy(new BigDecimal("290.00"));
        Cuenta destino = cuenta("0984445566", "Luis Mendez", "150.00", "500.00");
        when(cuentaRepository.findByNumeroCelularForUpdate("0984445566")).thenReturn(Optional.of(destino));
        when(cuentaRepository.findByNumeroCelularForUpdate("0991112233")).thenReturn(Optional.of(origen));

        assertThatThrownBy(() -> service.ejecutarMovimientoInterno(
                movimiento("0991112233", "0984445566", "20.00")))
                .isInstanceOf(BusinessConflictException.class)
                .hasMessageContaining("Limite diario excedido");

        assertThat(origen.getSaldo()).isEqualByComparingTo("500.00");
        assertThat(origen.getConsumidoHoy()).isEqualByComparingTo("290.00");
        assertThat(destino.getSaldo()).isEqualByComparingTo("150.00");
    }
}
