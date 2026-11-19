package com.fintech.billetera.cuentas.service;

import com.fintech.billetera.cuentas.domain.ContactoFrecuente;
import com.fintech.billetera.cuentas.domain.Cuenta;
import com.fintech.billetera.cuentas.repository.ContactoFrecuenteRepository;
import com.fintech.billetera.cuentas.repository.CuentaRepository;
import com.fintech.billetera.cuentas.web.dto.ContactoDto;
import com.fintech.billetera.cuentas.web.dto.CuentaDto;
import com.fintech.billetera.cuentas.web.dto.InstanciaDto;
import com.fintech.billetera.cuentas.web.dto.SaldoCriticoDto;
import com.fintech.billetera.persistence.audit.AuditoriaTecnicaDto;
import com.fintech.billetera.persistence.audit.DbAuditor;
import com.fintech.billetera.persistence.exception.ResourceNotFoundException;
import com.fintech.billetera.persistence.routing.PoliticaEnrutamiento;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CuentaConsultaServiceTest {

    private static final String INSTANCIA = "ms-cuentas-1:8081";
    private static final int PUERTO = 8081;
    private static final AuditoriaTecnicaDto AUDITORIA = new AuditoriaTecnicaDto(
            INSTANCIA, null, "REPLICA_1 (172.19.0.4:5432, recovery=true)",
            PoliticaEnrutamiento.ROUND_ROBIN_REPLICA);

    @Mock
    private CuentaRepository cuentaRepository;

    @Mock
    private ContactoFrecuenteRepository contactoFrecuenteRepository;

    @Mock
    private DbAuditor dbAuditor;

    private CuentaConsultaService service;

    @BeforeEach
    void setUp() {
        service = new CuentaConsultaService(
                cuentaRepository, contactoFrecuenteRepository, dbAuditor, INSTANCIA, PUERTO);
    }

    private Cuenta cuentaAna() {
        return new Cuenta("0991112233", "Ana Torres", new BigDecimal("500.00"), new BigDecimal("300.00"));
    }

    @Test
    void obtenerPorCelularDevuelveDtoYAuditoria() {
        when(cuentaRepository.findByNumeroCelular("0991112233")).thenReturn(Optional.of(cuentaAna()));
        when(dbAuditor.capturarAuditoriaActual()).thenReturn(AUDITORIA);

        OperacionResultado<CuentaDto> resultado = service.obtenerPorCelular("0991112233");

        assertThat(resultado.datos().numeroCelular()).isEqualTo("0991112233");
        assertThat(resultado.datos().titular()).isEqualTo("Ana Torres");
        assertThat(resultado.datos().saldo()).isEqualByComparingTo("500.00");
        assertThat(resultado.datos().consumidoHoy()).isEqualByComparingTo("0.00");
        assertThat(resultado.auditoria()).isEqualTo(AUDITORIA);
    }

    @Test
    void obtenerPorCelularLanzaNotFoundCuandoNoExiste() {
        when(cuentaRepository.findByNumeroCelular("0000000000")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.obtenerPorCelular("0000000000"))
                .isInstanceOf(ResourceNotFoundException.class)
                .hasMessageContaining("0000000000");
    }

    @Test
    void obtenerContactosDevuelveListaMapeada() {
        Cuenta cuenta = cuentaAna();
        when(cuentaRepository.existsByNumeroCelular("0991112233")).thenReturn(true);
        when(contactoFrecuenteRepository.findByCuentaPropietarioNumeroCelularOrderByAliasAsc("0991112233"))
                .thenReturn(List.of(
                        new ContactoFrecuente(cuenta, "0977778899", "Carla - Oficina"),
                        new ContactoFrecuente(cuenta, "0984445566", "Luis - Almuerzos")));
        when(dbAuditor.capturarAuditoriaActual()).thenReturn(AUDITORIA);

        OperacionResultado<List<ContactoDto>> resultado = service.obtenerContactos("0991112233");

        assertThat(resultado.datos()).hasSize(2);
        assertThat(resultado.datos().get(0).celularContacto()).isEqualTo("0977778899");
        assertThat(resultado.datos().get(0).alias()).isEqualTo("Carla - Oficina");
        assertThat(resultado.datos().get(1).alias()).isEqualTo("Luis - Almuerzos");
        assertThat(resultado.auditoria()).isEqualTo(AUDITORIA);
    }

    @Test
    void obtenerContactosLanzaNotFoundSiLaCuentaNoExiste() {
        when(cuentaRepository.existsByNumeroCelular("0000000000")).thenReturn(false);

        assertThatThrownBy(() -> service.obtenerContactos("0000000000"))
                .isInstanceOf(ResourceNotFoundException.class);
    }

    @Test
    void obtenerSaldoCriticoDevuelveSaldoYAuditoria() {
        when(cuentaRepository.findByNumeroCelular("0991112233")).thenReturn(Optional.of(cuentaAna()));
        when(dbAuditor.capturarAuditoriaActual()).thenReturn(AUDITORIA);

        OperacionResultado<SaldoCriticoDto> resultado = service.obtenerSaldoCritico("0991112233");

        assertThat(resultado.datos().numeroCelular()).isEqualTo("0991112233");
        assertThat(resultado.datos().saldo()).isEqualByComparingTo("500.00");
        assertThat(resultado.datos().limiteDiario()).isEqualByComparingTo("300.00");
        assertThat(resultado.datos().consultadoEn()).isNotNull();
        assertThat(resultado.auditoria()).isEqualTo(AUDITORIA);
    }

    @Test
    void obtenerSaldoCriticoLanzaNotFoundCuandoNoExiste() {
        when(cuentaRepository.findByNumeroCelular("0000000000")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.obtenerSaldoCritico("0000000000"))
                .isInstanceOf(ResourceNotFoundException.class);
    }

    @Test
    void obtenerDiagnosticoInstanciaDevuelveInstanciaPuertoYAuditoria() {
        when(dbAuditor.capturarAuditoriaActual()).thenReturn(AUDITORIA);

        OperacionResultado<InstanciaDto> resultado = service.obtenerDiagnosticoInstancia();

        assertThat(resultado.datos().instancia()).isEqualTo(INSTANCIA);
        assertThat(resultado.datos().puerto()).isEqualTo(PUERTO);
        assertThat(resultado.datos().timestamp()).isNotNull();
        assertThat(resultado.auditoria()).isEqualTo(AUDITORIA);
    }
}
