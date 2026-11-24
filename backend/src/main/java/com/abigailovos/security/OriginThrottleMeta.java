package com.abigailovos.security;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Duration;
import java.time.Instant;

@Entity
@Table(name = "auth_origin_throttle_meta")
class OriginThrottleMeta {
    private static final Duration CLOCK_SKEW = Duration.ofSeconds(5);
    @Id @Column(length = 16, nullable = false) private String id;
    @Column(name = "entry_count", nullable = false) private int entryCount;
    @Column(name = "last_observed_at") private Instant lastObservedAt;
    @Column(name = "last_pruned_at") private Instant lastPrunedAt;

    protected OriginThrottleMeta() {}

    /** Effective time never moves backwards across replicas using this database. */
    Instant observe(Instant now) {
        if (now == null || now.getEpochSecond() < 0 || entryCount < 0
                || (lastObservedAt != null && now.isBefore(lastObservedAt.minus(CLOCK_SKEW)))) return null;
        Instant effective = lastObservedAt != null && now.isBefore(lastObservedAt) ? lastObservedAt : now;
        lastObservedAt = effective;
        return effective;
    }

    int entryCount() { return entryCount; }
    boolean mayPrune(Instant now) {
        return lastPrunedAt == null || !lastPrunedAt.plus(Duration.ofMinutes(5)).isAfter(now);
    }
    void pruned(Instant now, int count) {
        if (count < 0 || count > entryCount) throw new IllegalStateException("Estado do limite de origem inválido.");
        entryCount -= count;
        lastPrunedAt = now;
    }
    void added() {
        if (entryCount == Integer.MAX_VALUE) throw new IllegalStateException("Estado do limite de origem inválido.");
        entryCount++;
    }
}
