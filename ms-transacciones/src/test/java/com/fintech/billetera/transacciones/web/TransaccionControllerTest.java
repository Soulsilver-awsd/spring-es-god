package com.fintech.billetera.transacciones.web;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import com.fintech.billetera.persistence.audit.AuditoriaTecnicaDto;
import com.fintech.billetera.persistence.audit.DbAuditor;
import com.fintech.billetera.persistence.exception.BaseErrorHandler;
import com.fintech.billetera.persistence.exception.ServiceUnavailableException;
import com.fintech.billetera.persistence.routing.PoliticaEnrutamiento;
import com.fintech.billetera.transacciones.domain.EstadoTransaccion;
import com.fintech.billetera.transacciones.service.OperacionRechazadaException;
import com.fintech.billetera.transacciones.service.ResultadoOperacion;
import com.fintech.billetera.transacciones.service.TransaccionConsultaService;
import com.fintech.billetera.transacciones.service.TransferenciaOrchestratorService;

@WebMvcTest(TransaccionController.class)
@Import({TransaccionesExceptionHandler.class, BaseErrorHandler.class})
class TransaccionControllerTest {

    private static final AuditoriaTecnicaDto AUDIT_PRIMARY = new AuditoriaTecnicaDto("ms-transacciones:8083",
            "ms-cuentas-2:8082", "PRIMARY (172.18.0.2:5432, recovery=false)", PoliticaEnrutamiento.ESCRITURA_DIRECTA);

    @Autowired
    private MockMvc mvc;

    @MockitoBean
    private TransferenciaOrchestratorService orchestrator;

    @MockitoBean
    private TransaccionConsultaService consultaService;

    @MockitoBean
    private DbAuditor dbAuditor;

    @BeforeEach
    void setUp() {
        when(dbAuditor.auditoriaSinConsultaSql(isNull())).thenReturn(
                new AuditoriaTecnicaDto("ms-transacciones:8083", null, "PRIMARY", PoliticaEnrutamiento.ESCRITURA_DIRECTA));
    }

    @Test
    void transferenciaExitosaResponde201ConComprobanteYAuditoria() throws Exception {
        when(orchestrator.transferir(any())).thenReturn(new ResultadoOperacion<>(new ComprobanteDto("TX-2026-0001",
                "0991112233", "0984445566", new BigDecimal("25.00"), "Pago almuerzo", EstadoTransaccion.EXITOSA,
                new BigDecimal("475.00"), OffsetDateTime.parse("2026-11-18T18:05:08Z")), AUDIT_PRIMARY));

        mvc.perform(post("/api/transacciones/transferir").contentType(MediaType.APPLICATION_JSON).content("""
                        {"celularOrigen":"0991112233","celularDestino":"0984445566","monto":25.00,"motivo":"Pago almuerzo"}"""))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.estado").value("OK"))
                .andExpect(jsonPath("$.datos.codigoComprobante").value("TX-2026-0001"))
                .andExpect(jsonPath("$.datos.estado").value("EXITOSA"))
                .andExpect(jsonPath("$.auditoriaTecnica.instanciaCuentasConsultada").value("ms-cuentas-2:8082"))
                .andExpect(jsonPath("$.auditoriaTecnica.politicaEnrutamiento").value("ESCRITURA_DIRECTA"));
    }

    @Test
    void datosInvalidosResponden400SinInvocarElOrquestador() throws Exception {
        mvc.perform(post("/api/transacciones/transferir").contentType(MediaType.APPLICATION_JSON).content("""
                        {"celularOrigen":"0991112233","celularDestino":"","monto":0,"motivo":"x"}"""))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.estado").value("ERROR"))
                .andExpect(jsonPath("$.mensaje").value(containsString("monto")))
                .andExpect(jsonPath("$.mensaje").value(containsString("celularDestino")));

        mvc.perform(post("/api/transacciones/transferir").contentType(MediaType.APPLICATION_JSON).content("""
                        {"celularOrigen":"0991112233","celularDestino":"0984445566","monto":1.234,"motivo":"x"}"""))
                .andExpect(status().isBadRequest());

        verify(orchestrator, never()).transferir(any());
    }

    @Test
    void rechazoDeNegocioResponde409ConLaAuditoriaDelServicio() throws Exception {
        when(orchestrator.transferir(any())).thenThrow(
                new OperacionRechazadaException(HttpStatus.CONFLICT, "Saldo insuficiente", AUDIT_PRIMARY));

        mvc.perform(post("/api/transacciones/transferir").contentType(MediaType.APPLICATION_JSON).content("""
                        {"celularOrigen":"0991112233","celularDestino":"0984445566","monto":9999.00,"motivo":"x"}"""))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.estado").value("ERROR"))
                .andExpect(jsonPath("$.mensaje").value("Saldo insuficiente"))
                .andExpect(jsonPath("$.datos").doesNotExist())
                .andExpect(jsonPath("$.auditoriaTecnica.instanciaCuentasConsultada").value("ms-cuentas-2:8082"));
    }

    @Test
    void msCuentasNoDisponibleResponde503() throws Exception {
        when(orchestrator.transferir(any()))
                .thenThrow(new ServiceUnavailableException("Servicio ms-cuentas no disponible temporalmente"));

        mvc.perform(post("/api/transacciones/transferir").contentType(MediaType.APPLICATION_JSON).content("""
                        {"celularOrigen":"0991112233","celularDestino":"0984445566","monto":5,"motivo":"x"}"""))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.mensaje").value("Servicio ms-cuentas no disponible temporalmente"));
    }

    @Test
    void historialYComprobanteDevuelvenApiResponse() throws Exception {
        TransaccionDto tx = new TransaccionDto("TX-2026-0001", "0991112233", "0984445566", new BigDecimal("25.00"),
                "Pago almuerzo", EstadoTransaccion.EXITOSA, OffsetDateTime.parse("2026-11-18T18:05:08Z"));
        when(consultaService.listarHistorial(anyString())).thenReturn(new ResultadoOperacion<>(List.of(tx),
                new AuditoriaTecnicaDto("ms-transacciones:8083", null, "REPLICA_2 (172.18.0.4:5432, recovery=true)",
                        PoliticaEnrutamiento.ROUND_ROBIN_REPLICA)));
        when(consultaService.consultarComprobanteCritico("TX-2026-0001")).thenReturn(new ResultadoOperacion<>(tx,
                new AuditoriaTecnicaDto("ms-transacciones:8083", null, "PRIMARY (172.18.0.2:5432, recovery=false)",
                        PoliticaEnrutamiento.LECTURA_CRITICA_PRIMARIO)));

        mvc.perform(get("/api/transacciones/historial/0991112233"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.datos[0].codigoComprobante").value("TX-2026-0001"))
                .andExpect(jsonPath("$.auditoriaTecnica.politicaEnrutamiento").value("ROUND_ROBIN_REPLICA"));
        mvc.perform(get("/api/transacciones/comprobante/TX-2026-0001"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.mensaje").value("Comprobante verificado en nodo primario"))
                .andExpect(jsonPath("$.auditoriaTecnica.politicaEnrutamiento").value("LECTURA_CRITICA_PRIMARIO"));
    }
}
