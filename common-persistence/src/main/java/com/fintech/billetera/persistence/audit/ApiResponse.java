package com.fintech.billetera.persistence.audit;

/**
 * Envoltorio JSON uniforme para todas las respuestas de negocio y errores controlados.
 */
public record ApiResponse<T>(
        String estado,
        String mensaje,
        T datos,
        AuditoriaTecnicaDto auditoriaTecnica
) {

    public static <T> ApiResponse<T> ok(String mensaje, T datos, AuditoriaTecnicaDto auditoria) {
        return new ApiResponse<>("OK", mensaje, datos, auditoria);
    }

    public static <T> ApiResponse<T> error(String mensaje, AuditoriaTecnicaDto auditoria) {
        return new ApiResponse<>("ERROR", mensaje, null, auditoria);
    }
}
