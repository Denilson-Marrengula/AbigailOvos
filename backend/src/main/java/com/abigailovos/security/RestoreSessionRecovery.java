package com.abigailovos.security;

import com.abigailovos.audit.AuditLog;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import java.time.Clock;
import java.time.Instant;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Invalidate restored tokens without deleting account, session or audit history. */
@Service
class RestoreSessionRecovery {
    private final EntityManager em;
    private final AuditLog audit;
    private final Clock clock;

    RestoreSessionRecovery(EntityManager em, AuditLog audit, Clock clock) {
        this.em = em;
        this.audit = audit;
        this.clock = clock;
    }

    /** Only with all HTTP writers stopped; a restored snapshot can resurrect old sessions. */
    @Transactional
    public int invalidateAll() {
        var accounts = em.createQuery("select u from AppUser u order by u.id", AppUser.class)
                .setLockMode(LockModeType.PESSIMISTIC_WRITE).getResultList();
        if (accounts.isEmpty()) throw new IllegalStateException("Nenhuma conta encontrada na base restaurada.");
        Instant now = clock.instant();
        if (now == null || now.getEpochSecond() < 0) throw new IllegalStateException("Relógio inválido.");
        for (AppUser account : accounts) account.invalidateSessions();
        audit.record("LOCAL_SECURITY_OPERATOR", "RESTORED_SESSIONS_INVALIDATED", "SYSTEM", "restored-database",
                "accounts=" + accounts.size());
        em.flush();
        return accounts.size();
    }
}
