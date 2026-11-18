package com.fintech.billetera.transacciones.domain;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * Registro del libro mayor {@code tx_db.transacciones}. Las cuentas se referencian por celular
 * (identificador de negocio), sin claves foraneas hacia {@code cuentas_db}.
 */
@Entity
@Table(name = "transacciones", schema = "tx_db")
public class Transaccion {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "codigo_comprobante", nullable = false, unique = true, length = 40)
    private String codigoComprobante;

    @Column(name = "celular_origen", nullable = false, length = 20)
    private String celularOrigen;

    @Column(name = "celular_destino", nullable = false, length = 20)
    private String celularDestino;

    @Column(name = "monto", nullable = false, precision = 14, scale = 2)
    private BigDecimal monto;

    @Column(name = "motivo", nullable = false, length = 160)
    private String motivo;

    @Enumerated(EnumType.STRING)
    @Column(name = "estado", nullable = false, length = 20)
    private EstadoTransaccion estado;

    @Column(name = "fecha_hora", nullable = false)
    private OffsetDateTime fechaHora;

    protected Transaccion() {
        // Requerido por JPA
    }

    public Transaccion(String codigoComprobante, String celularOrigen, String celularDestino, BigDecimal monto,
                       String motivo, EstadoTransaccion estado, OffsetDateTime fechaHora) {
        this.codigoComprobante = codigoComprobante;
        this.celularOrigen = celularOrigen;
        this.celularDestino = celularDestino;
        this.monto = monto;
        this.motivo = motivo;
        this.estado = estado;
        this.fechaHora = fechaHora;
    }

    public Long getId() {
        return id;
    }

    public String getCodigoComprobante() {
        return codigoComprobante;
    }

    public String getCelularOrigen() {
        return celularOrigen;
    }

    public String getCelularDestino() {
        return celularDestino;
    }

    public BigDecimal getMonto() {
        return monto;
    }

    public String getMotivo() {
        return motivo;
    }

    public EstadoTransaccion getEstado() {
        return estado;
    }

    public OffsetDateTime getFechaHora() {
        return fechaHora;
    }
}
