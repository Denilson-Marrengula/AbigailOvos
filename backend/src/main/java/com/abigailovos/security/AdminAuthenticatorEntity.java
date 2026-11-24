package com.abigailovos.security;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "admin_authenticators")
class AdminAuthenticatorEntity {
    @Id @Column(name = "account_id", length = 36, nullable = false)
    private String accountId;
    @Column(name = "active_secret", length = 192)
    private String activeSecret;
    @Column(name = "pending_secret", length = 192)
    private String pendingSecret;
    @Column(name = "pending_id", length = 36)
    private String pendingId;
    @Column(name = "pending_started_at")
    private Instant pendingStartedAt;
    @Column(name = "pending_expires_at")
    private Instant pendingExpiresAt;
    @Column(name = "not_before")
    private Instant notBefore;
    @Column(name = "last_accepted_step", nullable = false)
    private long lastAcceptedStep = -1;

    protected AdminAuthenticatorEntity() {}
    AdminAuthenticatorEntity(String accountId) { this.accountId = accountId; }

    String activeSecret() { return activeSecret; }
    String pendingSecret() { return pendingSecret; }
    String pendingId() { return pendingId; }
    Instant pendingStartedAt() { return pendingStartedAt; }
    Instant pendingExpiresAt() { return pendingExpiresAt; }
    Instant notBefore() { return notBefore; }
    long lastAcceptedStep() { return lastAcceptedStep; }

    void stage(String encrypted, String id, Instant started, Instant expiry) {
        pendingSecret = encrypted;
        pendingId = id;
        pendingStartedAt = started;
        pendingExpiresAt = expiry;
    }

    void activate(long step) {
        activeSecret = pendingSecret;
        pendingSecret = null;
        pendingId = null;
        pendingStartedAt = null;
        pendingExpiresAt = null;
        lastAcceptedStep = step;
    }

    void accept(long step) { lastAcceptedStep = step; }
}
