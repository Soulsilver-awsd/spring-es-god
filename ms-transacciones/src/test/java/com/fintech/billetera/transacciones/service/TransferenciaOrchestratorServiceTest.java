package com.fintech.billetera.transacciones.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.HttpStatus;

import com.fintech.billetera.persistence.audit.AuditoriaTecnicaDto;
import com.fintech.billetera.persistence.audit.DbAuditor;
import com.fintech.billetera.persistence.exception.BusinessValidationException;
import com.fintech.billetera.persistence.exception.ServiceUnavailableException;
import com.fintech.billetera.persistence.routing.PoliticaEnrutamiento;
import com.fintech.billetera.transacciones.client.CuentasHttpClient;
import com.fintech.billetera.transacciones.client.CuentasRechazoException;
import com.fintech.billetera.transacciones.client.MovimientoInternoResponse;
import com.fintech.billetera.transacciones.client.ResultadoMovimiento;
import com.fintech.billetera.transacciones.domain.EstadoTransaccion;
import com.fintech.billetera.transacciones.domain.Transaccion;
import com.fintech.billetera.transacciones.repository.TransaccionRepository;
import com.fintech.billetera.transacciones.web.ComprobanteDto;
import com.fintech.billetera.transacciones.web.TransferenciaRequest;

class TransferenciaOrchestratorServiceTest {

    private static final Clock CLOCK = Clock.fixed(Instant.parse("2026-11-18T18:05:08.123456789Z"), ZoneOffset.UTC);

    private final CuentasHttpClient cuentas = mock(CuentasHttpClient.class);
    private final TransaccionRepository repository = mock(TransaccionRepository.class);
    private final DbAuditor auditor = mock(DbAuditor.class);
    private TransferenciaOrchestratorService service;

    @BeforeEach
    void setUp() {
        when(repository.siguienteNumeroComprobante()).thenReturn(41L);
        when(repository.save(any(Transaccion.class))).thenAnswer(inv -> inv.getArgument(0));
        when(auditor.capturarAuditoriaActual(anyString())).thenAnswer(inv -> auditoria(inv.getArgument(0)));
        service = new TransferenciaOrchestratorService(cuentas, repository,
                new CodigoComprobanteGenerator(repository, CLOCK), auditor, CLOCK);
    }

    @Test
    void transferenciaExitosaRegistraComprobanteYAuditaLaInstanciaDeCuentas() {
        when(cuentas.ejecutarMovimiento("0991112233", "0984445566", new BigDecimal("25.00")))
                .thenReturn(movimiento("ms-cuentas-2:8082"));

        ResultadoOperacion<ComprobanteDto> resultado = service.transferir(request("25"));

        ComprobanteDto dto = resultado.datos();
        assertThat(dto.codigoComprobante()).isEqualTo("TX-2026-0041");
        assertThat(dto.estado()).isEqualTo(EstadoTransaccion.EXITOSA);
        assertThat(dto.monto()).isEqualByComparingTo("25.00").hasToString("25.00");
        assertThat(dto.nuevoSaldoOrigen()).isEqualByComparingTo("475.00");
        assertThat(dto.fechaHora()).hasToString("2026-11-18T18:05:08.123456Z");
        assertThat(resultado.auditoria().instanciaCuentasConsultada()).isEqualTo("ms-cuentas-2:8082");

        Transaccion guardada = guardada();
        assertThat(guardada.getEstado()).isEqualTo(EstadoTransaccion.EXITOSA);
        assertThat(guardada.getMotivo()).isEqualTo("Pago almuerzo");
    }

    @Test
    void rechazoDeNegocioRegistraRechazadaYPropagaElEstadoConAuditoria() {
        when(cuentas.ejecutarMovimiento(anyString(), anyString(), any()))
                .thenThrow(new CuentasRechazoException(HttpStatus.CONFLICT, "Saldo insuficiente", "ms-cuentas-1:8081"));

        assertThatThrownBy(() -> service.transferir(request("9999.00")))
                .isInstanceOfSatisfying(OperacionRechazadaException.class, ex -> {
                    assertThat(ex.getStatus()).isEqualTo(HttpStatus.CONFLICT);
                    assertThat(ex.getMessage()).isEqualTo("Saldo insuficiente");
                    assertThat(ex.getAuditoria().instanciaCuentasConsultada()).isEqualTo("ms-cuentas-1:8081");
                });

        Transaccion guardada = guardada();
        assertThat(guardada.getEstado()).isEqualTo(EstadoTransaccion.RECHAZADA);
        assertThat(guardada.getCodigoComprobante()).isEqualTo("TX-2026-0041");
    }

    @Test
    void siFallaElRegistroDelRechazoSeRespondeIgualElErrorDeNegocio() {
        when(cuentas.ejecutarMovimiento(anyString(), anyString(), any()))
                .thenThrow(new CuentasRechazoException(HttpStatus.CONFLICT, "Limite diario excedido", null));
        when(repository.siguienteNumeroComprobante()).thenThrow(new DataAccessResourceFailureException("primario caido"));

        assertThatThrownBy(() -> service.transferir(request("10")))
                .isInstanceOfSatisfying(OperacionRechazadaException.class,
                        ex -> assertThat(ex.getStatus()).isEqualTo(HttpStatus.CONFLICT));
    }

    @Test
    void sinMsCuentasDisponibleEs503SinRegistrarNiConsumirConsecutivo() {
        when(cuentas.ejecutarMovimiento(anyString(), anyString(), any()))
                .thenThrow(new ServiceUnavailableException("Servicio ms-cuentas no disponible temporalmente"));

        assertThatThrownBy(() -> service.transferir(request("10"))).isInstanceOf(ServiceUnavailableException.class);

        verify(repository, never()).save(any());
        verify(repository, never()).siguienteNumeroComprobante();
    }

    @Test
    void mismaCuentaEs400SinInvocarMsCuentas() {
        TransferenciaRequest mismaCuenta = new TransferenciaRequest("0991112233", "0991112233", BigDecimal.TEN, "x");

        assertThatThrownBy(() -> service.transferir(mismaCuenta)).isInstanceOf(BusinessValidationException.class);

        verifyNoInteractions(cuentas);
        verify(repository, never()).save(any());
    }

    @Test
    void fallaAlRegistrarTrasMovimientoAplicadoSePropaga() {
        when(cuentas.ejecutarMovimiento(anyString(), anyString(), any())).thenReturn(movimiento("ms-cuentas-1:8081"));
        when(repository.save(any())).thenThrow(new DataAccessResourceFailureException("primario caido"));

        assertThatThrownBy(() -> service.transferir(request("25")))
                .isInstanceOf(DataAccessResourceFailureException.class);
        verify(cuentas).ejecutarMovimiento(eq("0991112233"), eq("0984445566"), any());
    }

    private Transaccion guardada() {
        ArgumentCaptor<Transaccion> captor = ArgumentCaptor.forClass(Transaccion.class);
        verify(repository).save(captor.capture());
        return captor.getValue();
    }

    private static TransferenciaRequest request(String monto) {
        return new TransferenciaRequest("0991112233", "0984445566", new BigDecimal(monto), "Pago almuerzo");
    }

    private static ResultadoMovimiento movimiento(String instancia) {
        return new ResultadoMovimiento(new MovimientoInternoResponse("0991112233", "0984445566",
                new BigDecimal("25.00"), new BigDecimal("475.00"), new BigDecimal("175.00"), instancia), instancia);
    }

    private static AuditoriaTecnicaDto auditoria(String instancia) {
        return new AuditoriaTecnicaDto("ms-transacciones:8083", instancia,
                "PRIMARY (172.18.0.2:5432, recovery=false)", PoliticaEnrutamiento.ESCRITURA_DIRECTA);
    }
}
