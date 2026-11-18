# Especificación de Requisitos de Software (SRS)
## Sistema Distribuido de Billetera Digital y Transferencias P2P (*Fintech*)

**Estándar de referencia:** ISO/IEC/IEEE 29148 / IEEE 830  
**Versión del documento:** `1.0.0`  
**Fecha:** `2026-11-18`  
**Stack objetivo:** Java 21 · Spring Boot 3.4.3 · Spring Cloud 2024.0.1 (Eureka, Gateway, LoadBalancer) · PostgreSQL 17 (1 Primario + 2 Réplicas WAL) · Docker Compose

---

## 📁 Estructura Modular del SRS

Este SRS está organizado en carpetas temáticas dentro de `docs/srs/` para facilitar su lectura, revisión por pares y defensa técnica:

| Carpeta | Contenido | Documentos |
|---|---|---|
| **01 · Introducción** | Propósito, alcance, glosario, actores y marco de referencia | [01-proposito-alcance.md](01-introduccion/01-proposito-alcance.md) · [02-glosario-actores.md](01-introduccion/02-glosario-actores.md) · [03-referencias-contexto.md](01-introduccion/03-referencias-contexto.md) |
| **02 · Descripción General** | Perspectiva arquitectónica, funciones principales y supuestos/restricciones | [01-perspectiva-producto.md](02-descripcion-general/01-perspectiva-producto.md) · [02-funciones-sistema.md](02-descripcion-general/02-funciones-sistema.md) · [03-supuestos-dependencias.md](02-descripcion-general/03-supuestos-dependencias.md) |
| **03 · Requisitos Funcionales** | Especificación formal `RF-01` a `RF-12` (`ms-cuentas`, `ms-transacciones`, Gateway/Eureka) | [01-rf-cuentas-saldos.md](03-requisitos-funcionales/01-rf-cuentas-saldos.md) · [02-rf-transacciones-p2p.md](03-requisitos-funcionales/02-rf-transacciones-p2p.md) · [03-rf-gateway-descubrimiento.md](03-requisitos-funcionales/03-rf-gateway-descubrimiento.md) |
| **04 · Requisitos No Funcionales** | Disponibilidad, tolerancia a fallos, CQRS/consistencia, seguridad y reproducibilidad (`RNF-01` a `RNF-12`) | [01-rnf-disponibilidad-fallos.md](04-requisitos-no-funcionales/01-rnf-disponibilidad-fallos.md) · [02-rnf-consistencia-persistencia.md](04-requisitos-no-funcionales/02-rnf-consistencia-persistencia.md) · [03-rnf-seguridad-reproducibilidad.md](04-requisitos-no-funcionales/03-rnf-seguridad-reproducibilidad.md) |
| **05 · Interfaces y Datos** | Contratos REST, envoltorio `ApiResponse<T>`, esquemas `cuentas_db`/`tx_db` y secuencias | [01-contratos-api-rest.md](05-interfaces-y-datos/01-contratos-api-rest.md) · [02-modelo-datos-esquemas.md](05-interfaces-y-datos/02-modelo-datos-esquemas.md) · [03-flujos-secuencia.md](05-interfaces-y-datos/03-flujos-secuencia.md) |
| **06 · Verificación y Trazabilidad** | Criterios de aceptación para P01–P08 y matriz de trazabilidad hacia la rúbrica | [01-criterios-aceptacion-p01-p08.md](06-verificacion-y-trazabilidad/01-criterios-aceptacion-p01-p08.md) · [02-matriz-trazabilidad.md](06-verificacion-y-trazabilidad/02-matriz-trazabilidad.md) |

---

## 🎯 Resumen Ejecutivo del Dominio

El sistema implementa una plataforma distribuida de **Billetera Digital y Transferencias P2P (estilo DeUna! / PayPhone)** compuesta por:
- **`ms-cuentas` (2 instancias activas):** Propietario del esquema `cuentas_db` (`cuentas`, `contactos_frecuentes`). Gestiona saldos, estado de cuenta, límites diarios y validaciones financieras.
- **`ms-transacciones` (1 instancia):** Propietario del esquema `tx_db` (`transacciones`). Orquesta transferencias entre cuentas llamando dinámicamente a `lb://ms-cuentas`, persiste el libro mayor (*ledger*) y emite comprobantes.
- **`eureka-server` y `api-gateway`:** Registro dinámico de servicios y punto único de entrada HTTP con balanceo mediante Spring Cloud LoadBalancer.
- **Clúster PostgreSQL 17 Replicado (1 Primario + 2 Réplicas):** Escrituras y lecturas críticas de saldo/comprobante dirigidas al **Primario**; consultas ordinarias (perfil/saldo en pantalla principal, contactos frecuentes e historial mensual) distribuidas en **Round-Robin** entre las **2 Réplicas** con detección de fallos y reincorporación controlada.
