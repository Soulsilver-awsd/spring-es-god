package com.fintech.billetera.transacciones.web;

import java.util.List;

import jakarta.validation.Valid;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fintech.billetera.persistence.audit.ApiResponse;
import com.fintech.billetera.transacciones.service.ResultadoOperacion;
import com.fintech.billetera.transacciones.service.TransaccionConsultaService;
import com.fintech.billetera.transacciones.service.TransferenciaOrchestratorService;

@RestController
@RequestMapping("/api/transacciones")
public class TransaccionController {

    private final TransferenciaOrchestratorService orchestrator;
    private final TransaccionConsultaService consultaService;

    public TransaccionController(TransferenciaOrchestratorService orchestrator,
                                 TransaccionConsultaService consultaService) {
        this.orchestrator = orchestrator;
        this.consultaService = consultaService;
    }

    @PostMapping("/transferir")
    public ResponseEntity<ApiResponse<ComprobanteDto>> transferir(@Valid @RequestBody TransferenciaRequest request) {
        ResultadoOperacion<ComprobanteDto> resultado = orchestrator.transferir(request);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.ok("Transferencia realizada con exito", resultado.datos(), resultado.auditoria()));
    }

    @GetMapping("/historial/{celular}")
    public ApiResponse<List<TransaccionDto>> historial(@PathVariable String celular) {
        ResultadoOperacion<List<TransaccionDto>> resultado = consultaService.listarHistorial(celular);
        return ApiResponse.ok("Historial obtenido", resultado.datos(), resultado.auditoria());
    }

    @GetMapping("/comprobante/{codigo}")
    public ApiResponse<TransaccionDto> comprobante(@PathVariable String codigo) {
        ResultadoOperacion<TransaccionDto> resultado = consultaService.consultarComprobanteCritico(codigo);
        return ApiResponse.ok("Comprobante verificado en nodo primario", resultado.datos(), resultado.auditoria());
    }
}
