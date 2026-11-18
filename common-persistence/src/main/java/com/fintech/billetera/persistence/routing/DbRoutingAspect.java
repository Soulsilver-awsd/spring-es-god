package com.fintech.billetera.persistence.routing;

import com.fintech.billetera.persistence.annotation.TipoNodo;
import com.fintech.billetera.persistence.annotation.UsarNodo;
import com.fintech.billetera.persistence.health.ReplicaHealthTracker;
import jakarta.servlet.http.HttpServletRequest;
import java.lang.reflect.Method;
import java.util.Optional;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.reflect.MethodSignature;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.aop.support.AopUtils;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.AnnotationUtils;
import org.springframework.core.annotation.Order;
import org.springframework.dao.DataAccessException;
import org.springframework.transaction.TransactionException;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

/**
 * Aspecto AOP ejecutado con la maxima precedencia (antes de @Transactional)
 * para fijar el DataSource destino en DbContextHolder y rescatar lecturas ante fallo de replica.
 */
@Aspect
@Order(Ordered.HIGHEST_PRECEDENCE)
public class DbRoutingAspect {

    private static final Logger log = LoggerFactory.getLogger(DbRoutingAspect.class);
    public static final String HEADER_CONSISTENCIA = "X-Consistencia";
    public static final String VALOR_CRITICA = "CRITICA";
    public static final String ATTR_DB_NODE = "app.audit.dbNode";
    public static final String ATTR_DB_FALLBACK = "app.audit.dbFallback";

    private final ReplicaHealthTracker replicaHealthTracker;

    public DbRoutingAspect(ReplicaHealthTracker replicaHealthTracker) {
        this.replicaHealthTracker = replicaHealthTracker;
    }

    @Around("@annotation(com.fintech.billetera.persistence.annotation.UsarNodo) || "
            + "@within(com.fintech.billetera.persistence.annotation.UsarNodo)")
    public Object routeAndExecute(ProceedingJoinPoint pjp) throws Throwable {
        UsarNodo usarNodo = resolveUsarNodo(pjp);
        if (usarNodo == null) {
            return pjp.proceed();
        }

        boolean forcePrimary = usarNodo.value() == TipoNodo.PRIMARY || isCriticalConsistencyHeaderPresent();
        if (forcePrimary) {
            PoliticaEnrutamiento politica = usarNodo.escritura()
                    ? PoliticaEnrutamiento.ESCRITURA_DIRECTA
                    : PoliticaEnrutamiento.LECTURA_CRITICA_PRIMARIO;
            return executeOnNode(pjp, DbKey.PRIMARY, politica, false);
        }

        Optional<DbKey> replicaOpt = replicaHealthTracker.selectNextHealthyReplica();
        if (replicaOpt.isEmpty()) {
            log.warn("Sin replicas saludables disponibles; redirigiendo lectura a PRIMARY");
            return executeOnNode(pjp, DbKey.PRIMARY, PoliticaEnrutamiento.FAILOVER_REPLICA, true);
        }

        DbKey chosenReplica = replicaOpt.get();
        try {
            return executeOnNode(pjp, chosenReplica, PoliticaEnrutamiento.ROUND_ROBIN_REPLICA, false);
        } catch (DataAccessException | TransactionException ex) {
            log.warn("Fallo en lectura sobre {}: {}. Activando failover transparente.",
                    chosenReplica, ex.getMessage());
            replicaHealthTracker.markUnhealthy(chosenReplica, ex.getMessage());
            DbKey fallbackNode = replicaHealthTracker.selectAlternativeHealthyReplica(chosenReplica)
                    .orElse(DbKey.PRIMARY);
            return executeOnNode(pjp, fallbackNode, PoliticaEnrutamiento.FAILOVER_REPLICA, true);
        }
    }

    private Object executeOnNode(
            ProceedingJoinPoint pjp,
            DbKey node,
            PoliticaEnrutamiento policy,
            boolean fallbackUsed) throws Throwable {
        DbContextHolder.set(node, policy, fallbackUsed);
        storeRequestAttributes(node, fallbackUsed);
        try {
            Object result = pjp.proceed();
            replicaHealthTracker.recordQuery(node);
            return result;
        } finally {
            DbContextHolder.clear();
        }
    }

    private UsarNodo resolveUsarNodo(ProceedingJoinPoint pjp) {
        MethodSignature signature = (MethodSignature) pjp.getSignature();
        Class<?> targetClass = pjp.getTarget() != null
                ? AopUtils.getTargetClass(pjp.getTarget())
                : signature.getDeclaringType();
        Method specificMethod = AopUtils.getMostSpecificMethod(signature.getMethod(), targetClass);
        UsarNodo onMethod = AnnotationUtils.findAnnotation(specificMethod, UsarNodo.class);
        if (onMethod != null) {
            return onMethod;
        }
        return AnnotationUtils.findAnnotation(targetClass, UsarNodo.class);
    }

    private boolean isCriticalConsistencyHeaderPresent() {
        HttpServletRequest request = currentHttpRequest();
        if (request == null) {
            return false;
        }
        String header = request.getHeader(HEADER_CONSISTENCIA);
        return VALOR_CRITICA.equalsIgnoreCase(header != null ? header.trim() : null);
    }

    private void storeRequestAttributes(DbKey node, boolean fallbackUsed) {
        HttpServletRequest request = currentHttpRequest();
        if (request != null) {
            request.setAttribute(ATTR_DB_NODE, node.name());
            request.setAttribute(ATTR_DB_FALLBACK, String.valueOf(fallbackUsed));
        }
    }

    private HttpServletRequest currentHttpRequest() {
        if (RequestContextHolder.getRequestAttributes() instanceof ServletRequestAttributes attrs) {
            return attrs.getRequest();
        }
        return null;
    }
}
