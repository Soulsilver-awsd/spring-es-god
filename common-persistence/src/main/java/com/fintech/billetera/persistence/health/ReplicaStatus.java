package com.fintech.billetera.persistence.health;

import com.fintech.billetera.persistence.routing.DbKey;
import java.time.Instant;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Estado mutable por replica PostgreSQL supervisado por ReplicaHealthTracker.
 */
public class ReplicaStatus {

    private final DbKey nodo;
    private volatile boolean available;
    private volatile int consecutiveSuccesses;
    private volatile int consecutiveFailures;
    private volatile String lastReplayLsn;
    private volatile Instant lastCheckedAt;
    private volatile String lastError;
    private final AtomicLong servedQueries = new AtomicLong(0);

    public ReplicaStatus(DbKey nodo, boolean initialAvailable) {
        this.nodo = nodo;
        this.available = initialAvailable;
    }

    public DbKey getNodo() {
        return nodo;
    }

    public boolean isAvailable() {
        return available;
    }

    public void setAvailable(boolean available) {
        this.available = available;
    }

    public int getConsecutiveSuccesses() {
        return consecutiveSuccesses;
    }

    public void setConsecutiveSuccesses(int consecutiveSuccesses) {
        this.consecutiveSuccesses = consecutiveSuccesses;
    }

    public int getConsecutiveFailures() {
        return consecutiveFailures;
    }

    public void setConsecutiveFailures(int consecutiveFailures) {
        this.consecutiveFailures = consecutiveFailures;
    }

    public String getLastReplayLsn() {
        return lastReplayLsn;
    }

    public void setLastReplayLsn(String lastReplayLsn) {
        this.lastReplayLsn = lastReplayLsn;
    }

    public Instant getLastCheckedAt() {
        return lastCheckedAt;
    }

    public void setLastCheckedAt(Instant lastCheckedAt) {
        this.lastCheckedAt = lastCheckedAt;
    }

    public String getLastError() {
        return lastError;
    }

    public void setLastError(String lastError) {
        this.lastError = lastError;
    }

    public long incrementServedQueries() {
        return servedQueries.incrementAndGet();
    }

    public long getServedQueries() {
        return servedQueries.get();
    }
}
