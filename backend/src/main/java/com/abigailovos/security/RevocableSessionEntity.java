package com.abigailovos.security;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "auth_sessions")
class RevocableSessionEntity {
    @Id @Column(name = "token_hash", nullable = false, length = 64)
    private String tokenHash;
    @Column(name = "account_id", nullable = false, length = 36)
    private String accountId;
    @Column(name = "account_epoch", nullable = false)
    private long accountEpoch;
    @Column(name = "created_at", nullable = false)
    private Instant createdAt;
    @Column(name = "last_seen_at", nullable = false)
    private Instant lastSeenAt;
    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;
    @Column(name = "revoked_at")
    private Instant revokedAt;

    protected RevocableSessionEntity() {}

    RevocableSessionEntity(String tokenHash, AppUser account, Instant now, Instant expiresAt) {
        this.tokenHash = tokenHash;
        this.accountId = account.getId();
        this.accountEpoch = account.sessionEpoch();
        this.createdAt = now;
        this.lastSeenAt = now;
        this.expiresAt = expiresAt;
    }

    String accountId() { return accountId; }
    long accountEpoch() { return accountEpoch; }
    Instant createdAt() { return createdAt; }
    Instant lastSeenAt() { return lastSeenAt; }
    Instant expiresAt() { return expiresAt; }
    Instant revokedAt() { return revokedAt; }
    void touch(Instant now) { lastSeenAt = now; }
    void revoke(Instant now) { if (revokedAt == null) revokedAt = now; }
}
