package com.fintech.billetera.persistence.annotation;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Indica al aspecto de enrutamiento si el metodo o clase debe ejecutarse
 * contra el nodo Primario o distribuirse entre las Replicas de lectura.
 */
@Target({ElementType.METHOD, ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
public @interface UsarNodo {

    TipoNodo value();

    boolean escritura() default false;
}
