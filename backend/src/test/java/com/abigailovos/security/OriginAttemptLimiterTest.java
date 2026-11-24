package com.abigailovos.security;

import jakarta.persistence.EntityManager;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;

/** Synthetic H2 only. Does not test proxy trust or the active HTTP Basic flow. */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:origin_throttle;MODE=MySQL;DB_CLOSE_DELAY=-1",
        "ABIGAIL_AUTH_ORIGIN_KEY=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
        "abigail.origin.max-entries=3"
})
@Import(OriginAttemptLimiterTest.FixedClock.class)
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_EACH_TEST_METHOD)
class OriginAttemptLimiterTest {
    private static final Instant NOW = Instant.parse("2026-11-15T10:00:00Z");
    @Autowired OriginAttemptLimiter limiter;
    @Autowired JdbcTemplate jdbc;
    @Autowired EntityManager em;
    @Autowired Clock clock;
    @Autowired TransactionTemplate transactions;

    @TestConfiguration(proxyBeanMethods = false)
    static class FixedClock {
        @Bean @Primary Clock testOriginClock() { return Clock.fixed(NOW, ZoneOffset.UTC); }
    }

    @BeforeEach void addSyntheticSingleton() {
        // H2 creates tables from entities, not Flyway; V16 seeds this row in real migrations.
        jdbc.update("insert into auth_origin_throttle_meta (id,entry_count) values ('global',0)");
    }

    @Test void limitsEachOriginAndNormalizesEquivalentIpv6() {
        for (int i = 0; i < 15; i++) assertThat(limiter.charge("2001:db8::1")).isTrue();
        for (int i = 0; i < 15; i++) assertThat(limiter.charge("2001:0db8:0:0:0:0:0:1")).isTrue();
        assertThat(limiter.charge("2001:db8::1")).isFalse();
        assertThat(limiter.charge("192.0.2.1")).isTrue();
        assertThat(jdbc.queryForObject("select count(*) from auth_origin_attempts", Integer.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject("select count(*) from auth_origin_attempts where origin_hash like '%192.0.2%'", Integer.class)).isZero();
    }

    @Test void rejectsUntrustedHeaderStringsAndMissingKey() {
        assertThat(limiter.charge("192.0.2.1, 203.0.113.5")).isFalse();
        assertThat(limiter.charge("example.org")).isFalse();
        assertThat(limiter.charge(null)).isFalse();
        var withoutKey = new OriginAttemptLimiter(em, clock, "", 3);
        assertThatThrownBy(() -> withoutKey.charge("192.0.2.1"))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("Chave");
        assertThat(jdbc.queryForObject("select count(*) from auth_origin_attempts", Integer.class)).isZero();
    }

    @Test void capsCardinalityAndPrunesOnlyStaleThrottleEntries() {
        assertThat(limiter.charge("192.0.2.1")).isTrue();
        assertThat(limiter.charge("192.0.2.2")).isTrue();
        assertThat(limiter.charge("192.0.2.3")).isTrue();
        assertThat(limiter.charge("192.0.2.4")).isFalse();
        jdbc.update("update auth_origin_attempts set last_request_at=?", java.sql.Timestamp.from(NOW.minusSeconds(3601)));
        jdbc.update("update auth_origin_throttle_meta set last_pruned_at=? where id='global'", java.sql.Timestamp.from(NOW.minusSeconds(301)));
        assertThat(limiter.charge("192.0.2.4")).isTrue();
        assertThat(jdbc.queryForObject("select count(*) from auth_origin_attempts", Integer.class)).isEqualTo(1);
        assertThat(jdbc.queryForObject("select entry_count from auth_origin_throttle_meta where id='global'", Integer.class)).isEqualTo(1);
    }

    @Test void outerRollbackDoesNotRefundAnAttempt() {
        transactions.executeWithoutResult(status -> {
            assertThat(limiter.charge("192.0.2.1")).isTrue();
            status.setRollbackOnly();
        });
        assertThat(jdbc.queryForObject("select request_count from auth_origin_attempts", Integer.class)).isEqualTo(1);
    }

    @Test void concurrentAttemptsArePrechargedAtomically() throws Exception {
        var start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(8)) {
            var futures = new ArrayList<java.util.concurrent.Future<Boolean>>();
            for (int i = 0; i < 35; i++) futures.add(executor.submit(() -> {
                if (!start.await(5, TimeUnit.SECONDS)) throw new IllegalStateException("Prazo excedido");
                return limiter.charge("192.0.2.1");
            }));
            start.countDown();
            int accepted = 0;
            for (var result : futures) if (result.get(15, TimeUnit.SECONDS)) accepted++;
            assertThat(accepted).isEqualTo(30);
        }
        assertThat(jdbc.queryForObject("select request_count from auth_origin_attempts", Integer.class)).isEqualTo(30);
    }
}
