package com.fintech.billetera.cuentas.web;

import com.fintech.billetera.cuentas.service.CuentaConsultaService;
import com.fintech.billetera.cuentas.service.MovimientoCuentaService;
import com.fintech.billetera.cuentas.service.OperacionResultado;
import com.fintech.billetera.cuentas.web.dto.ContactoDto;
import com.fintech.billetera.cuentas.web.dto.CrearCuentaRequest;
import com.fintech.billetera.cuentas.web.dto.CuentaDto;
import com.fintech.billetera.cuentas.web.dto.InstanciaDto;
import com.fintech.billetera.cuentas.web.dto.MovimientoInternoRequest;
import com.fintech.billetera.cuentas.web.dto.MovimientoInternoResponse;
import com.fintech.billetera.cuentas.web.dto.SaldoCriticoDto;
import com.fintech.billetera.persistence.audit.ApiResponse;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * API REST de cuentas, saldos, contactos y movimientos internos.
 * Las cabeceras X-Service-Instance / X-Db-Node / X-Db-Fallback las agrega
 * AuditoriaResponseAdvice de common-persistence.
 */
@RestController
@RequestMapping("/api/cuentas")
public class CuentaController {

    private final CuentaConsultaService consultaService;
    private final MovimientoCuentaService movimientoService;

    public CuentaController(
            CuentaConsultaService consultaService,
            MovimientoCuentaService movimientoService) {
        this.consultaService = consultaService;
        this.movimientoService = movimientoService;
    }

    @GetMapping("/{celular}")
    public ApiResponse<CuentaDto> obtenerCuenta(@PathVariable String celular) {
        OperacionResultado<CuentaDto> resultado = consultaService.obtenerPorCelular(celular);
        return ApiResponse.ok("Cuenta consultada correctamente", resultado.datos(), resultado.auditoria());
    }

    @GetMapping("/{celular}/contactos")
    public ApiResponse<List<ContactoDto>> obtenerContactos(@PathVariable String celular) {
        OperacionResultado<List<ContactoDto>> resultado = consultaService.obtenerContactos(celular);
        return ApiResponse.ok("Contactos frecuentes obtenidos", resultado.datos(), resultado.auditoria());
    }

    @GetMapping("/{celular}/saldo-critico")
    public ApiResponse<SaldoCriticoDto> obtenerSaldoCritico(@PathVariable String celular) {
        OperacionResultado<SaldoCriticoDto> resultado = consultaService.obtenerSaldoCritico(celular);
        return ApiResponse.ok("Saldo critico verificado en nodo primario", resultado.datos(), resultado.auditoria());
    }

    @GetMapping("/instancia")
    public ApiResponse<InstanciaDto> obtenerInstancia() {
        OperacionResultado<InstanciaDto> resultado = consultaService.obtenerDiagnosticoInstancia();
        return ApiResponse.ok("Instancia operativa", resultado.datos(), resultado.auditoria());
    }

    @PostMapping
    public ResponseEntity<ApiResponse<CuentaDto>> crearCuenta(@Valid @RequestBody CrearCuentaRequest request) {
        OperacionResultado<CuentaDto> resultado = movimientoService.crearCuenta(request);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.ok("Cuenta creada exitosamente", resultado.datos(), resultado.auditoria()));
    }

    @PostMapping("/movimiento-interno")
    public ApiResponse<MovimientoInternoResponse> ejecutarMovimientoInterno(
            @Valid @RequestBody MovimientoInternoRequest request) {
        OperacionResultado<MovimientoInternoResponse> resultado =
                movimientoService.ejecutarMovimientoInterno(request);
        return ApiResponse.ok("Movimiento interno aplicado", resultado.datos(), resultado.auditoria());
    }
}
