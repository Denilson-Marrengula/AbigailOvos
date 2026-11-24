package com.abigailovos.audit;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "audit_events")
class AuditEvent {
    @Id @Column(length = 36, updatable = false) private String id;
    @Column(nullable = false, length = 150, updatable = false) private String actor;
    @Column(nullable = false, length = 50, updatable = false) private String action;
    @Column(name = "target_type", nullable = false, length = 30, updatable = false) private String targetType;
    @Column(name = "target_id", nullable = false, length = 36, updatable = false) private String targetId;
    @Column(nullable = false, length = 255, updatable = false) private String detail;
    @Column(name = "occurred_at", nullable = false, updatable = false) private Instant occurredAt;

    protected AuditEvent() {}

    AuditEvent(String actor, String action, String targetType, String targetId, String detail) {
        this.id = UUID.randomUUID().toString();
        this.actor = actor;
        this.action = action;
        this.targetType = targetType;
        this.targetId = targetId;
        this.detail = detail;
        this.occurredAt = Instant.now();
    }

    String id() { return id; }
    String actor() { return actor; }
    String action() { return action; }
    String targetType() { return targetType; }
    String targetId() { return targetId; }
    String detail() { return detail; }
    Instant occurredAt() { return occurredAt; }
}
