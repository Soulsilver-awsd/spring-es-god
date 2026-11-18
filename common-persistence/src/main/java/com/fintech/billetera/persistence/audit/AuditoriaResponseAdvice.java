package com.fintech.billetera.persistence.audit;

import com.fintech.billetera.persistence.routing.DbRoutingAspect;
import com.fintech.billetera.persistence.routing.PoliticaEnrutamiento;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.core.MethodParameter;
import org.springframework.http.MediaType;
import org.springframework.http.converter.HttpMessageConverter;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.http.server.ServletServerHttpRequest;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.ResponseBodyAdvice;

/**
 * Agrega automaticamente las cabeceras HTTP de trazabilidad en cada respuesta ApiResponse.
 */
@RestControllerAdvice
public class AuditoriaResponseAdvice implements ResponseBodyAdvice<Object> {

    public static final String HEADER_SERVICE_INSTANCE = "X-Service-Instance";
    public static final String HEADER_DB_NODE = "X-Db-Node";
    public static final String HEADER_DB_FALLBACK = "X-Db-Fallback";

    private final DbAuditor dbAuditor;

    public AuditoriaResponseAdvice(DbAuditor dbAuditor) {
        this.dbAuditor = dbAuditor;
    }

    @Override
    public boolean supports(MethodParameter returnType, Class<? extends HttpMessageConverter<?>> converterType) {
        return true;
    }

    @Override
    public Object beforeBodyWrite(
            Object body,
            MethodParameter returnType,
            MediaType selectedContentType,
            Class<? extends HttpMessageConverter<?>> selectedConverterType,
            ServerHttpRequest request,
            ServerHttpResponse response) {

        response.getHeaders().set(HEADER_SERVICE_INSTANCE, dbAuditor.getServicioOrigen());

        if (body instanceof ApiResponse<?> apiResponse && apiResponse.auditoriaTecnica() != null) {
            AuditoriaTecnicaDto audit = apiResponse.auditoriaTecnica();
            if (audit.servicioOrigen() != null) {
                response.getHeaders().set(HEADER_SERVICE_INSTANCE, audit.servicioOrigen());
            }
            if (audit.nodoBaseDatos() != null) {
                response.getHeaders().set(HEADER_DB_NODE, audit.nodoBaseDatos());
            }
            boolean fallback = audit.politicaEnrutamiento() == PoliticaEnrutamiento.FAILOVER_REPLICA
                    || isFallbackFlagInRequest(request);
            response.getHeaders().set(HEADER_DB_FALLBACK, String.valueOf(fallback));
        } else if (request instanceof ServletServerHttpRequest servletRequest) {
            HttpServletRequest httpReq = servletRequest.getServletRequest();
            Object nodeAttr = httpReq.getAttribute(DbRoutingAspect.ATTR_DB_NODE);
            Object fbAttr = httpReq.getAttribute(DbRoutingAspect.ATTR_DB_FALLBACK);
            if (nodeAttr != null) {
                response.getHeaders().set(HEADER_DB_NODE, nodeAttr.toString());
            }
            if (fbAttr != null) {
                response.getHeaders().set(HEADER_DB_FALLBACK, fbAttr.toString());
            }
        }

        return body;
    }

    private boolean isFallbackFlagInRequest(ServerHttpRequest request) {
        if (request instanceof ServletServerHttpRequest servletRequest) {
            Object attr = servletRequest.getServletRequest().getAttribute(DbRoutingAspect.ATTR_DB_FALLBACK);
            return Boolean.TRUE.equals(attr) || "true".equals(String.valueOf(attr));
        }
        return false;
    }
}
