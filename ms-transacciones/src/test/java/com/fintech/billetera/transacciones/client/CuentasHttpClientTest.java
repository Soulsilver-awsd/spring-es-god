package com.fintech.billetera.transacciones.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withException;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import java.io.IOException;
import java.math.BigDecimal;
import java.time.Duration;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import com.fintech.billetera.persistence.exception.ServiceUnavailableException;
import com.fintech.billetera.transacciones.config.CuentasClientProperties;

class CuentasHttpClientTest {

    private static final String URL = "http://ms-cuentas/api/cuentas/movimiento-interno";
    private static final CuentasClientProperties PROPS =
            new CuentasClientProperties("http://ms-cuentas", Duration.ofSeconds(3), Duration.ofSeconds(5));

    private MockRestServiceServer server;
    private CuentasHttpClient client;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder();
        server = MockRestServiceServer.bindTo(builder).build();
        client = new CuentasHttpClient(builder, PROPS);
    }

    @Test
    void usaElNombreLogicoYExtraeLaInstanciaDeLaCabecera() {
        server.expect(requestTo(URL))
                .andExpect(method(HttpMethod.POST))
                .andExpect(content().json("""
                        {"celularOrigen":"0991112233","celularDestino":"0984445566","monto":25.00}"""))
                .andRespond(withSuccess(okBody("ms-cuentas-2:8082"), MediaType.APPLICATION_JSON)
                        .header("X-Service-Instance", "ms-cuentas-2:8082"));

        ResultadoMovimiento resultado = client.ejecutarMovimiento("0991112233", "0984445566", new BigDecimal("25.00"));

        assertThat(resultado.instanciaAtendio()).isEqualTo("ms-cuentas-2:8082");
        assertThat(resultado.movimiento().nuevoSaldoOrigen()).isEqualByComparingTo("475.00");
        assertThat(resultado.movimiento().nuevoSaldoDestino()).isEqualByComparingTo("175.00");
        server.verify();
    }

    @Test
    void sinCabeceraUsaServicioOrigenDeLaAuditoria() {
        server.expect(requestTo(URL))
                .andRespond(withSuccess(okBody("ms-cuentas-1:8081"), MediaType.APPLICATION_JSON));

        assertThat(client.ejecutarMovimiento("0991112233", "0984445566", BigDecimal.TEN).instanciaAtendio())
                .isEqualTo("ms-cuentas-1:8081");
    }

    @Test
    void conflictoDeNegocioSePropagaComoRechazoConMensajeEInstancia() {
        server.expect(requestTo(URL))
                .andRespond(withStatus(HttpStatus.CONFLICT)
                        .contentType(MediaType.APPLICATION_JSON)
                        .header("X-Service-Instance", "ms-cuentas-1:8081")
                        .body(errorBody("Saldo insuficiente", "ms-cuentas-1:8081")));

        assertThatThrownBy(() -> client.ejecutarMovimiento("0991112233", "0984445566", new BigDecimal("9999")))
                .isInstanceOfSatisfying(CuentasRechazoException.class, ex -> {
                    assertThat(ex.getStatus()).isEqualTo(HttpStatus.CONFLICT);
                    assertThat(ex.getMessage()).isEqualTo("Saldo insuficiente");
                    assertThat(ex.getInstanciaCuentas()).isEqualTo("ms-cuentas-1:8081");
                });
    }

    @Test
    void cuentaInexistenteYValidacionConservanSuCodigo() {
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.NOT_FOUND)
                .contentType(MediaType.APPLICATION_JSON).body(errorBody("Cuenta no encontrada", "ms-cuentas-2:8082")));
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.BAD_REQUEST)
                .contentType(MediaType.APPLICATION_JSON).body(errorBody("monto invalido", "ms-cuentas-2:8082")));

        assertThatThrownBy(() -> client.ejecutarMovimiento("0991112233", "0000000000", BigDecimal.ONE))
                .isInstanceOfSatisfying(CuentasRechazoException.class, ex -> {
                    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
                    // Sin cabecera X-Service-Instance: se toma de auditoriaTecnica.servicioOrigen
                    assertThat(ex.getInstanciaCuentas()).isEqualTo("ms-cuentas-2:8082");
                });
        assertThatThrownBy(() -> client.ejecutarMovimiento("0991112233", "0984445566", BigDecimal.ONE))
                .isInstanceOfSatisfying(CuentasRechazoException.class,
                        ex -> assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST));
    }

    @Test
    void errorSinCuerpoJsonUsaElTextoDeEstado() {
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.CONFLICT).body("conflicto"));

        assertThatThrownBy(() -> client.ejecutarMovimiento("0991112233", "0984445566", BigDecimal.ONE))
                .isInstanceOfSatisfying(CuentasRechazoException.class, ex -> {
                    assertThat(ex.getStatus()).isEqualTo(HttpStatus.CONFLICT);
                    assertThat(ex.getMessage()).isNotBlank();
                });
    }

    @Test
    void errorDelServidorODeConexionEs503() {
        server.expect(requestTo(URL)).andRespond(withServerError());
        server.expect(requestTo(URL)).andRespond(withException(new IOException("Connection refused")));

        assertThatThrownBy(() -> client.ejecutarMovimiento("0991112233", "0984445566", BigDecimal.ONE))
                .isInstanceOf(ServiceUnavailableException.class);
        assertThatThrownBy(() -> client.ejecutarMovimiento("0991112233", "0984445566", BigDecimal.ONE))
                .isInstanceOf(ServiceUnavailableException.class)
                .hasMessage(CuentasHttpClient.MENSAJE_NO_DISPONIBLE);
    }

    @Test
    void otroCodigo4xxNoSeTrataComoRechazoDeNegocio() {
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.UNSUPPORTED_MEDIA_TYPE));

        assertThatThrownBy(() -> client.ejecutarMovimiento("0991112233", "0984445566", BigDecimal.ONE))
                .isInstanceOf(ServiceUnavailableException.class);
    }

    @Test
    void sinInstanciasEnElRegistroEs503() {
        // BlockingLoadBalancerClient lanza IllegalStateException("No instances available for ms-cuentas").
        RestClient.Builder builder = RestClient.builder().requestInterceptor((request, body, execution) -> {
            throw new IllegalStateException("No instances available for ms-cuentas");
        });
        CuentasHttpClient sinInstancias = new CuentasHttpClient(builder, PROPS);

        assertThatThrownBy(() -> sinInstancias.ejecutarMovimiento("0991112233", "0984445566", BigDecimal.ONE))
                .isInstanceOf(ServiceUnavailableException.class);
    }

    @Test
    void respuestaSinDatosEs503() {
        server.expect(requestTo(URL)).andRespond(withSuccess("""
                {"estado":"OK","mensaje":"x","datos":null,"auditoriaTecnica":null}""", MediaType.APPLICATION_JSON)
                .headers(new HttpHeaders()));

        assertThatThrownBy(() -> client.ejecutarMovimiento("0991112233", "0984445566", BigDecimal.ONE))
                .isInstanceOf(ServiceUnavailableException.class);
    }

    private static String okBody(String instancia) {
        return """
                {"estado":"OK","mensaje":"Movimiento interno aplicado",
                 "datos":{"celularOrigen":"0991112233","celularDestino":"0984445566","monto":25.00,
                          "nuevoSaldoOrigen":475.00,"nuevoSaldoDestino":175.00,"instanciaAtendio":"%s"},
                 "auditoriaTecnica":{"servicioOrigen":"%s","instanciaCuentasConsultada":null,
                          "nodoBaseDatos":"PRIMARY (172.18.0.2:5432, recovery=false)",
                          "politicaEnrutamiento":"ESCRITURA_DIRECTA"}}""".formatted(instancia, instancia);
    }

    private static String errorBody(String mensaje, String instancia) {
        return """
                {"estado":"ERROR","mensaje":"%s","datos":null,
                 "auditoriaTecnica":{"servicioOrigen":"%s","instanciaCuentasConsultada":null,
                          "nodoBaseDatos":"PRIMARY","politicaEnrutamiento":"ESCRITURA_DIRECTA"}}"""
                .formatted(mensaje, instancia);
    }
}
