package com.fintech.billetera.persistence.config;

import com.fintech.billetera.persistence.routing.DbKey;
import java.util.ArrayList;
import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Propiedades externalizadas para el nodo Primario y las Replicas PostgreSQL.
 */
@ConfigurationProperties(prefix = "app.db")
public class PersistenceRoutingProperties {

    private long healthCheckIntervalMs = 3000;
    private int recoverySuccessThreshold = 2;
    private int probeQueryTimeoutSeconds = 2;
    private NodeConfig primary = new NodeConfig();
    private List<ReplicaNodeConfig> replicas = new ArrayList<>();

    public long getHealthCheckIntervalMs() {
        return healthCheckIntervalMs;
    }

    public void setHealthCheckIntervalMs(long healthCheckIntervalMs) {
        this.healthCheckIntervalMs = healthCheckIntervalMs;
    }

    public int getRecoverySuccessThreshold() {
        return recoverySuccessThreshold;
    }

    public void setRecoverySuccessThreshold(int recoverySuccessThreshold) {
        this.recoverySuccessThreshold = recoverySuccessThreshold;
    }

    public int getProbeQueryTimeoutSeconds() {
        return probeQueryTimeoutSeconds;
    }

    public void setProbeQueryTimeoutSeconds(int probeQueryTimeoutSeconds) {
        this.probeQueryTimeoutSeconds = probeQueryTimeoutSeconds;
    }

    public NodeConfig getPrimary() {
        return primary;
    }

    public void setPrimary(NodeConfig primary) {
        this.primary = primary;
    }

    public List<ReplicaNodeConfig> getReplicas() {
        return replicas;
    }

    public void setReplicas(List<ReplicaNodeConfig> replicas) {
        this.replicas = replicas;
    }

    public static class NodeConfig {
        private String url;
        private String username;
        private String password;
        private int maximumPoolSize = 10;
        private int minimumIdle = 2;
        private long connectionTimeoutMs = 5000;
        private long validationTimeoutMs = 2000;

        public String getUrl() {
            return url;
        }

        public void setUrl(String url) {
            this.url = url;
        }

        public String getUsername() {
            return username;
        }

        public void setUsername(String username) {
            this.username = username;
        }

        public String getPassword() {
            return password;
        }

        public void setPassword(String password) {
            this.password = password;
        }

        public int getMaximumPoolSize() {
            return maximumPoolSize;
        }

        public void setMaximumPoolSize(int maximumPoolSize) {
            this.maximumPoolSize = maximumPoolSize;
        }

        public int getMinimumIdle() {
            return minimumIdle;
        }

        public void setMinimumIdle(int minimumIdle) {
            this.minimumIdle = minimumIdle;
        }

        public long getConnectionTimeoutMs() {
            return connectionTimeoutMs;
        }

        public void setConnectionTimeoutMs(long connectionTimeoutMs) {
            this.connectionTimeoutMs = connectionTimeoutMs;
        }

        public long getValidationTimeoutMs() {
            return validationTimeoutMs;
        }

        public void setValidationTimeoutMs(long validationTimeoutMs) {
            this.validationTimeoutMs = validationTimeoutMs;
        }
    }

    public static class ReplicaNodeConfig extends NodeConfig {
        private DbKey key;

        public ReplicaNodeConfig() {
            setMinimumIdle(1);
            setConnectionTimeoutMs(2000);
            setValidationTimeoutMs(1500);
        }

        public DbKey getKey() {
            return key;
        }

        public void setKey(DbKey key) {
            this.key = key;
        }
    }
}
