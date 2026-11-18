package com.fintech.billetera.transacciones.client;

import java.math.BigDecimal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import com.fintech.billetera.persistence.audit.ApiResponse;
import com.fintech.billetera.persistence.exception.ServiceUnavailableException;
import com.fintech.billetera.transacciones.config.CuentasClientProperties;

/**
 * Cliente de {@code POST http://ms-cuentas/api/cuentas/movimiento-interno} (RF-06).
 *
 * <p>La URL usa siempre el nombre logico {@code ms-cuentas}; el {@code RestClient.Builder}
 * {@code @LoadBalanced} lo resuelve contra Eureka. Mapeo de errores (SDD 04, seccion 2):</p>
 * <ul>
 *   <li>{@code 400}/{@code 404}/{@code 409} de ms-cuentas: {@link CuentasRechazoException} con el mismo estado.</li>
 *   <li>{@code 5xx}, timeout/conexion o sin instancias en Eureka: {@link ServiceUnavailableException} (503).</li>
 * </ul>
 */
@Component
public class CuentasHttpClient {

    static final String MOVIMIENTO_INTERNO_PATH = "/api/cuentas/movimiento-interno";
    static final String HEADER_SERVICE_INSTANCE = "X-Service-Instance";
    static final String MENSAJE_NO_DISPONIBLE = "Servicio ms-cuentas no disponible temporalmente";

    private static final Logger log = LoggerFactory.getLogger(CuentasHttpClient.class);
    private static final ParameterizedTypeReference<ApiResponse<MovimientoInternoResponse>> RESPUESTA =
            new ParameterizedTypeReference<>() {
            };

    private final RestClient restClient;

    public CuentasHttpClient(RestClient.Builder loadBalancedRestClientBuilder, CuentasClientProperties properties) {
        this.restClient = loadBalancedRestClientBuilder.baseUrl(properties.baseUrl()).build();
    }

    public ResultadoMovimiento ejecutarMovimiento(String celularOrigen, String celularDestino, BigDecimal monto) {
        MovimientoInternoRequest request = new MovimientoInternoRequest(celularOrigen, celularDestino, monto);
        try {
            ResponseEntity<ApiResponse<MovimientoInternoResponse>> response = restClient.post()
                    .uri(MOVIMIENTO_INTERNO_PATH)
                    .contentType(MediaType.APPLICATION_JSON)
                    .accept(MediaType.APPLICATION_JSON)
                    .body(request)
                    .retrieve()
                    .toEntity(RESPUESTA);
            ApiResponse<MovimientoInternoResponse> body = response.getBody();
            if (body == null || body.datos() == null) {
                throw new ServiceUnavailableException("ms-cuentas respondio sin datos del movimiento");
            }
            return new ResultadoMovimiento(body.datos(), instancia(response.getHeaders(), body));
        } catch (HttpClientErrorException ex) {
            HttpStatus status = HttpStatus.resolve(ex.getStatusCode().value());
            ApiResponse<?> error = leerError(ex);
            String mensaje = error != null && error.mensaje() != null ? error.mensaje() : ex.getStatusText();
            String instancia = instancia(ex.getResponseHeaders(), error);
            if (status == HttpStatus.BAD_REQUEST || status == HttpStatus.NOT_FOUND || status == HttpStatus.CONFLICT) {
                throw new CuentasRechazoException(status, mensaje, instancia);
            }
            log.error("Respuesta inesperada {} de ms-cuentas: {}", ex.getStatusCode(), mensaje);
            throw new ServiceUnavailableException(MENSAJE_NO_DISPONIBLE, ex);
        } catch (HttpServerErrorException | ResourceAccessException ex) {
            // ResourceAccessException por timeout de lectura es ambiguo: ms-cuentas pudo aplicar el movimiento.
            log.error("ms-cuentas no disponible al mover {} de {} a {}: {}", monto, celularOrigen, celularDestino,
                    ex.getMessage());
            throw new ServiceUnavailableException(MENSAJE_NO_DISPONIBLE, ex);
        } catch (IllegalStateException ex) {
            // BlockingLoadBalancerClient: "No instances available for ms-cuentas" (ninguna instancia UP en Eureka).
            log.warn("Sin instancias de ms-cuentas en el registro: {}", ex.getMessage());
            throw new ServiceUnavailableException(MENSAJE_NO_DISPONIBLE, ex);
        } catch (RestClientException ex) {
            log.error("Error invocando ms-cuentas: {}", ex.getMessage());
            throw new ServiceUnavailableException(MENSAJE_NO_DISPONIBLE, ex);
        }
    }

    /** Instancia real de ms-cuentas: cabecera {@code X-Service-Instance} o {@code auditoriaTecnica.servicioOrigen}. */
    private static String instancia(HttpHeaders headers, ApiResponse<?> body) {
        String header = headers != null ? headers.getFirst(HEADER_SERVICE_INSTANCE) : null;
        if (header != null && !header.isBlank()) {
            return header;
        }
        return body != null && body.auditoriaTecnica() != null ? body.auditoriaTecnica().servicioOrigen() : null;
    }

    private static ApiResponse<?> leerError(HttpClientErrorException ex) {
        try {
            return ex.getResponseBodyAs(ApiResponse.class);
        } catch (RuntimeException parseError) {
            return null;
        }
    }
}
