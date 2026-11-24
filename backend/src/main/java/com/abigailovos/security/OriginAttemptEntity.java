package com.abigailovos.security;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import java.time.Duration;
import java.time.Instant;

@Entity
@Table(name = "auth_origin_attempts", indexes = @Index(name = "idx_auth_origin_last_request", columnList = "last_request_at"))
class OriginAttemptEntity {
    private static final int MAX_REQUESTS = 30;
    private static final Duration WINDOW = Duration.ofMinutes(5);
    @Id @Column(name = "origin_hash", length = 64, nullable = false) private String originHash;
    @Column(name = "window_started_at", nullable = false) private Instant windowStartedAt;
    @Column(name = "last_request_at", nullable = false) private Instant lastRequestAt;
    @Column(name = "request_count", nullable = false) private int requestCount;

    protected OriginAttemptEntity() {}
    OriginAttemptEntity(String originHash, Instant now) {
        this.originHash = originHash;
        this.windowStartedAt = now;
        this.lastRequestAt = now;
    }

    /** Charge before authentication, including successful attempts. */
    boolean charge(Instant now) {
        if (windowStartedAt == null || lastRequestAt == null || now.isBefore(windowStartedAt)
                || now.isBefore(lastRequestAt) || requestCount < 0 || requestCount > MAX_REQUESTS) return false;
        lastRequestAt = now;
        if (!windowStartedAt.plus(WINDOW).isAfter(now)) {
            windowStartedAt = now;
            requestCount = 0;
        }
        if (requestCount >= MAX_REQUESTS) return false;
        requestCount++;
        return true;
    }
}
