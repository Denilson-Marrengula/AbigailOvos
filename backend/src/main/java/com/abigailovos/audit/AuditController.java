package com.abigailovos.audit;

import jakarta.persistence.EntityManager;
import java.time.Instant;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
class AuditController {
    private final EntityManager em;
    AuditController(EntityManager em) { this.em = em; }

    record View(String id, String actor, String action, String targetType, String targetId,
            String detail, Instant occurredAt) {}

    @GetMapping("/api/audit/events")
    @Transactional(readOnly = true)
    List<View> events(@RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        if (page < 0 || page > 10_000 || size < 1 || size > 100)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Paginação inválida");
        return em.createQuery("select e from AuditEvent e order by e.occurredAt desc, e.id desc", AuditEvent.class)
                .setFirstResult(page * size).setMaxResults(size).getResultList().stream()
                .map(e -> new View(e.id(), e.actor(), e.action(), e.targetType(), e.targetId(), e.detail(), e.occurredAt()))
                .toList();
    }
}
