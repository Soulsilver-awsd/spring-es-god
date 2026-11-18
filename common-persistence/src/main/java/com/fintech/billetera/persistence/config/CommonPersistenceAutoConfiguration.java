package com.fintech.billetera.persistence.config;

import com.fintech.billetera.persistence.audit.AuditoriaResponseAdvice;
import com.fintech.billetera.persistence.audit.DbAuditor;
import com.fintech.billetera.persistence.audit.DbEstadoController;
import com.fintech.billetera.persistence.exception.BaseErrorHandler;
import com.fintech.billetera.persistence.health.ReplicaHealthTracker;
import com.fintech.billetera.persistence.routing.DbRoutingAspect;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.EnableAspectJAutoProxy;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Autoconfiguracion Spring Boot para habilitar el enrutamiento multi-nodo,
 * monitoreo de replicas, auditoria tecnica y manejo global de errores.
 */
@AutoConfiguration(before = {DataSourceAutoConfiguration.class, FlywayAutoConfiguration.class})
@ConditionalOnProperty(prefix = "app.db.primary", name = "url")
@EnableScheduling
@EnableAspectJAutoProxy
@EnableConfigurationProperties(PersistenceRoutingProperties.class)
@Import({
    MultiNodeDataSourceConfig.class,
    DbEstadoController.class,
    AuditoriaResponseAdvice.class,
    BaseErrorHandler.class
})
public class CommonPersistenceAutoConfiguration {

    @Bean
    public DbRoutingAspect dbRoutingAspect(ReplicaHealthTracker replicaHealthTracker) {
        return new DbRoutingAspect(replicaHealthTracker);
    }

    @Bean
    public DbAuditor dbAuditor(
            JdbcTemplate jdbcTemplate,
            @Value("${app.instance-id:${spring.application.name:servicio}:${server.port:8080}}") String servicioOrigen) {
        return new DbAuditor(jdbcTemplate, servicioOrigen);
    }
}
