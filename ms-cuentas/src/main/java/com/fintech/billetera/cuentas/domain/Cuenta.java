package com.fintech.billetera.cuentas.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;

/**
 * Billetera digital identificada por el numero de celular del titular.
 */
@Entity
@Table(name = "cuentas", schema = "cuentas_db")
public class Cuenta {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "numero_celular", nullable = false, unique = true, length = 20)
    private String numeroCelular;

    @Column(name = "titular", nullable = false, length = 120)
    private String titular;

    @Column(name = "saldo", nullable = false, precision = 14, scale = 2)
    private BigDecimal saldo;

    @Column(name = "limite_diario", nullable = false, precision = 14, scale = 2)
    private BigDecimal limiteDiario;

    @Column(name = "consumido_hoy", nullable = false, precision = 14, scale = 2)
    private BigDecimal consumidoHoy;

    @Enumerated(EnumType.STRING)
    @Column(name = "estado", nullable = false, length = 20)
    private EstadoCuenta estado;

    protected Cuenta() {
        // Requerido por JPA.
    }

    public Cuenta(String numeroCelular, String titular, BigDecimal saldo, BigDecimal limiteDiario) {
        this.numeroCelular = numeroCelular;
        this.titular = titular;
        this.saldo = normalizar(saldo);
        this.limiteDiario = normalizar(limiteDiario);
        this.consumidoHoy = BigDecimal.ZERO.setScale(2);
        this.estado = EstadoCuenta.ACTIVA;
    }

    private static BigDecimal normalizar(BigDecimal valor) {
        return valor == null ? null : valor.setScale(2, java.math.RoundingMode.HALF_UP);
    }

    public Long getId() {
        return id;
    }

    public String getNumeroCelular() {
        return numeroCelular;
    }

    public void setNumeroCelular(String numeroCelular) {
        this.numeroCelular = numeroCelular;
    }

    public String getTitular() {
        return titular;
    }

    public void setTitular(String titular) {
        this.titular = titular;
    }

    public BigDecimal getSaldo() {
        return saldo;
    }

    public void setSaldo(BigDecimal saldo) {
        this.saldo = saldo;
    }

    public BigDecimal getLimiteDiario() {
        return limiteDiario;
    }

    public void setLimiteDiario(BigDecimal limiteDiario) {
        this.limiteDiario = limiteDiario;
    }

    public BigDecimal getConsumidoHoy() {
        return consumidoHoy;
    }

    public void setConsumidoHoy(BigDecimal consumidoHoy) {
        this.consumidoHoy = consumidoHoy;
    }

    public EstadoCuenta getEstado() {
        return estado;
    }

    public void setEstado(EstadoCuenta estado) {
        this.estado = estado;
    }
}
