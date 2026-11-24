package com.abigailovos.security;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Duration;
import java.time.Instant;

/** Access only while holding the account write lock, then this row's write lock. */
@Entity
@Table(name = "auth_account_attempts")
class AccountAttemptEntity {
    private static final Duration WINDOW = Duration.ofMinutes(5);
    private static final int MAX_FAILURES = 5;

    @Id @Column(name = "account_id", nullable = false, length = 36)
    private String accountId;
    @Column(name = "window_started_at", nullable = false)
    private Instant windowStartedAt;
    @Column(name = "last_attempt_at", nullable = false)
    private Instant lastAttemptAt;
    @Column(name = "failure_count", nullable = false)
    private int failureCount;
    @Column(name = "blocked_until")
    private Instant blockedUntil;

    protected AccountAttemptEntity() {}
    AccountAttemptEntity(String accountId, Instant now) {
        this.accountId = accountId;
        this.windowStartedAt = now;
        this.lastAttemptAt = now;
    }

    /** A backward clock or inconsistent persisted state fails closed. */
    boolean blocked(Instant now) {
        return windowStartedAt == null || lastAttemptAt == null || now.isBefore(windowStartedAt)
                || now.isBefore(lastAttemptAt) || failureCount < 0
                || failureCount > MAX_FAILURES || (failureCount >= MAX_FAILURES && blockedUntil == null)
                || (blockedUntil != null && blockedUntil.isAfter(now));
    }

    void failed(Instant now) {
        if (blocked(now)) throw new IllegalStateException("Tentativa bloqueada.");
        if (blockedUntil != null || !windowStartedAt.plus(WINDOW).isAfter(now)) reset(now);
        failureCount++;
        lastAttemptAt = now;
        if (failureCount == MAX_FAILURES) blockedUntil = now.plus(WINDOW);
    }

    void reset(Instant now) {
        windowStartedAt = now;
        lastAttemptAt = now;
        failureCount = 0;
        blockedUntil = null;
    }
}
