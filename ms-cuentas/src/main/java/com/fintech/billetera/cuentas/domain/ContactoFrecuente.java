package com.fintech.billetera.cuentas.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

/**
 * Contacto frecuente asociado a la cuenta propietaria de una billetera.
 */
@Entity
@Table(name = "contactos_frecuentes", schema = "cuentas_db")
public class ContactoFrecuente {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "cuenta_propietario_id", nullable = false)
    private Cuenta cuentaPropietario;

    @Column(name = "celular_contacto", nullable = false, length = 20)
    private String celularContacto;

    @Column(name = "alias", nullable = false, length = 80)
    private String alias;

    protected ContactoFrecuente() {
        // Requerido por JPA.
    }

    public ContactoFrecuente(Cuenta cuentaPropietario, String celularContacto, String alias) {
        this.cuentaPropietario = cuentaPropietario;
        this.celularContacto = celularContacto;
        this.alias = alias;
    }

    public Long getId() {
        return id;
    }

    public Cuenta getCuentaPropietario() {
        return cuentaPropietario;
    }

    public void setCuentaPropietario(Cuenta cuentaPropietario) {
        this.cuentaPropietario = cuentaPropietario;
    }

    public String getCelularContacto() {
        return celularContacto;
    }

    public void setCelularContacto(String celularContacto) {
        this.celularContacto = celularContacto;
    }

    public String getAlias() {
        return alias;
    }

    public void setAlias(String alias) {
        this.alias = alias;
    }
}
