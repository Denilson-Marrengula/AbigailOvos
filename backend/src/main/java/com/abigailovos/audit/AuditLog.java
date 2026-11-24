package com.abigailovos.audit;

import jakarta.persistence.EntityManager;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuditLog {
    private final EntityManager em;
    public AuditLog(EntityManager em) { this.em = em; }

    /** Caller supplies only fixed metadata, never request bodies, personal data or credentials. */
    @Transactional(propagation = Propagation.MANDATORY)
    public void record(String actor, String action, String targetType, String targetId, String detail) {
        em.persist(new AuditEvent(actor, action, targetType, targetId, detail));
    }
}
