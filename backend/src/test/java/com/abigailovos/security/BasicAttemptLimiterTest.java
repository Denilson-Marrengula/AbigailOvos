package com.abigailovos.security;

import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

class BasicAttemptLimiterTest {
    @Test void failuresExpireWithoutSuccessfulRequestsClearingThem() {
        AtomicLong now = new AtomicLong();
        BasicAttemptLimiter limiter = new BasicAttemptLimiter(now::get);
        for (int i = 0; i < 5; i++) {
            assertThat(limiter.begin("one")).isZero();
            limiter.finish("one", true);
            if (i < 4) {
                assertThat(limiter.begin("one")).isZero();
                limiter.finish("one", false);
            }
        }
        assertThat(limiter.begin("one")).isEqualTo(300);
        assertThat(limiter.begin("two")).isZero();
        limiter.finish("two", false);
        now.addAndGet(TimeUnit.SECONDS.toNanos(299));
        assertThat(limiter.begin("one")).isEqualTo(1);
        now.addAndGet(TimeUnit.SECONDS.toNanos(1));
        assertThat(limiter.begin("one")).isZero();
        limiter.finish("one", false);
    }

    @Test void boundedStorageFailsClosedAndExpires() {
        AtomicLong now = new AtomicLong();
        BasicAttemptLimiter limiter = new BasicAttemptLimiter(now::get);
        for (int i = 0; i < 10_000; i++) {
            assertThat(limiter.begin("address-" + i)).isZero();
            limiter.finish("address-" + i, true);
        }
        assertThat(limiter.begin("new-address")).isEqualTo(60);
        now.addAndGet(TimeUnit.MINUTES.toNanos(5));
        assertThat(limiter.begin("new-address")).isZero();
        limiter.finish("new-address", false);
    }

    @Test void concurrentInFlightResultsAreAllCounted() {
        BasicAttemptLimiter limiter = new BasicAttemptLimiter(() -> 1L);
        for (int i = 0; i < 6; i++) assertThat(limiter.begin("one")).isZero();
        for (int i = 0; i < 6; i++) limiter.finish("one", true);
        assertThat(limiter.begin("one")).isEqualTo(300);
    }
}
