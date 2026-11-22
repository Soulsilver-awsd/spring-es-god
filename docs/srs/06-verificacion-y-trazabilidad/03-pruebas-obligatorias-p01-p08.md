## **04. Pruebas experimentales obligatorias**

Cada escenario deberá ejecutarse y documentarse. No se aceptarán capturas de configuración como sustituto de una prueba funcional.

### **P01 · Descubrimiento dinámico**

Verificar que las instancias se registran correctamente en Eureka y pueden localizarse por nombre lógico.

**Evidencias:**

- Registro de servicios.
- Identificación de instancias.
- Solicitudes funcionales.

### **P02 · Balanceo HTTP**

Ejecutar al menos 100 solicitudes contra un servicio con dos instancias y registrar qué instancia responde cada solicitud.

**Evidencias:**

- Distribución observada.
- Total de respuestas exitosas.
- Errores.

### **P03 · Fallo de instancia**

Detener una instancia del microservicio y comprobar que el sistema continúa atendiendo solicitudes mediante otra instancia.

**Evidencias:**

- Solicitudes antes, durante y después del fallo.
- Tiempo observado de recuperación.

### **P04 · Comunicación entre servicios**

Ejecutar una operación de negocio que requiera una llamada real de un microservicio a otro mediante descubrimiento dinámico.

**Evidencias:**

- Trazas de solicitud y respuesta.
- Resultado funcional.
- Manejo de errores.

### **P05 · Enrutamiento de base de datos**

Demostrar que las escrituras utilizan el primario y las consultas ordinarias se distribuyen entre las dos réplicas.

**Evidencias:**

- Identificación del nodo utilizado.
- Consultas SQL.
- Registros de aplicación.

### **P06 · Fallo de réplica PostgreSQL**

Detener una réplica y comprobar que las consultas continúan mediante la réplica restante.

**Evidencias:**

- Estado de contenedores.
- Resultados de consultas.
- Registros del mecanismo de selección.

### **P07 · Consistencia de lectura**

Crear un registro y consultarlo inmediatamente mediante una operación crítica dirigida al primario.

**Evidencias:**

- Secuencia de solicitudes.
- Resultado.
- Justificación de la política aplicada.

### **P08 · Recuperación de réplica**

Reiniciar la réplica detenida, comprobar su recuperación y verificar que vuelve a participar en las consultas.

**Evidencias:**

- Estado de replicación.
- Reincorporación.
- Consultas atendidas.
