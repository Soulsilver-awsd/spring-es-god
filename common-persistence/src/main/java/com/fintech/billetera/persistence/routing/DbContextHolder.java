package com.fintech.billetera.persistence.routing;

/**
 * Almacena por hilo el nodo objetivo, la politica aplicada y si hubo failover
 * antes de que TransactionInterceptor abra la conexion JDBC.
 */
public final class DbContextHolder {

    private static final ThreadLocal<DbKey> CURRENT_NODE = new ThreadLocal<>();
    private static final ThreadLocal<PoliticaEnrutamiento> CURRENT_POLICY = new ThreadLocal<>();
    private static final ThreadLocal<Boolean> FALLBACK_USED = new ThreadLocal<>();

    private DbContextHolder() {
    }

    public static void set(DbKey dbKey, PoliticaEnrutamiento policy, boolean fallbackUsed) {
        CURRENT_NODE.set(dbKey);
        CURRENT_POLICY.set(policy);
        FALLBACK_USED.set(fallbackUsed);
    }

    public static DbKey getDbKey() {
        return CURRENT_NODE.get();
    }

    public static PoliticaEnrutamiento getPolicy() {
        return CURRENT_POLICY.get();
    }

    public static boolean isFallbackUsed() {
        return Boolean.TRUE.equals(FALLBACK_USED.get());
    }

    public static void clear() {
        CURRENT_NODE.remove();
        CURRENT_POLICY.remove();
        FALLBACK_USED.remove();
    }
}
