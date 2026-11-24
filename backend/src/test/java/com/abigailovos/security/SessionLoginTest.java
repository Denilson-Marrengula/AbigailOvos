package com.abigailovos.security;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import static org.assertj.core.api.Assertions.*;

/** Tests session login against synthetic H2 accounts. */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:session_login;MODE=MySQL;DB_CLOSE_DELAY=-1",
        "ABIGAIL_MFA_KEY=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
})
@Import(SessionLoginTest.FixedClock.class)
class SessionLoginTest {
    private static final Instant NOW = Instant.parse("2026-11-14T10:00:00Z");
    private static final String PASSWORD = "correct-test-password";
    @Autowired SessionLogin login;
    @Autowired AppUserRepository users;
    @Autowired PasswordEncoder passwords;
    @Autowired AdminAuthenticator mfa;
    @Autowired RevocableSessions sessions;
    @Autowired JdbcTemplate jdbc;

    @TestConfiguration(proxyBeanMethods = false)
    static class FixedClock {
        @Bean @Primary Clock clockForTest() { return Clock.fixed(NOW, ZoneOffset.UTC); }
    }

    @Test void sellerGetsARevocableSessionWithoutAnAuthenticator() {
        AppUser user = account("SELLER");
        var outcome = login.authenticate(user.getUsername(), PASSWORD);
        assertThat(outcome.accepted()).isTrue();
        assertThat(outcome.role()).isEqualTo("SELLER");
        assertThat(outcome.toString()).doesNotContain(outcome.issued().token()).doesNotContain(PASSWORD);
        assertThat(sessions.authenticate(outcome.issued().token(), NOW)).isPresent();
        sessions.revoke(outcome.issued().token(), NOW);
        assertThat(sessions.authenticate(outcome.issued().token(), NOW)).isEmpty();
    }

    @Test void administratorUsesPasswordWithoutAnAuthenticator() {
        AppUser user = account("ADMIN");
        assertThat(login.authenticate(user.getUsername(), "wrong-test-password").accepted()).isFalse();
        var outcome = login.authenticate(user.getUsername(), PASSWORD);
        assertThat(outcome.accepted()).isTrue();
        assertThat(outcome.role()).isEqualTo("ADMIN");
        assertThat(sessions.authenticate(outcome.issued().token(), NOW)).isPresent();
        assertThat(jdbc.queryForObject("select count(*) from admin_authenticators where account_id=?", Integer.class, user.getId())).isZero();
    }

    @Test void historicalAuthenticatorDoesNotAffectLoginAndIsPreserved() {
        AppUser user = account("ADMIN");
        var enrollment = AdminAuthenticatorTest.stageWithDistinctNext(mfa, user, NOW);
        byte[] secret = AdminAuthenticatorTest.decode(enrollment.secret());
        try {
            String initial = TotpCodes.generate(secret, NOW.getEpochSecond() / 30, 6);
            assertThat(mfa.confirm(user.getId(), enrollment.id(), initial, NOW)).isTrue();
            String stored = jdbc.queryForObject("select active_secret from admin_authenticators where account_id=?", String.class, user.getId());
            Long step = jdbc.queryForObject("select last_accepted_step from admin_authenticators where account_id=?", Long.class, user.getId());
            var outcome = login.authenticate(user.getUsername(), PASSWORD);
            assertThat(outcome.accepted()).isTrue();
            assertThat(sessions.authenticate(outcome.issued().token(), NOW)).isPresent();
            assertThat(jdbc.queryForObject("select active_secret from admin_authenticators where account_id=?", String.class, user.getId())).isEqualTo(stored);
            assertThat(jdbc.queryForObject("select last_accepted_step from admin_authenticators where account_id=?", Long.class, user.getId())).isEqualTo(step);
        } finally { Arrays.fill(secret, (byte) 0); }
    }

    @Test void failuresPersistPerAccountAndRecoverAfterTheBlock() {
        AppUser user = account("SELLER");
        AppUser other = account("SELLER");
        for (int i = 0; i < 5; i++) assertThat(login.authenticate(user.getUsername(), "wrong-test-password").accepted()).isFalse();
        assertThat(login.authenticate(user.getUsername(), PASSWORD).accepted()).isFalse();
        assertThat(login.authenticate(other.getUsername(), PASSWORD).accepted()).isTrue();
        assertThat(jdbc.queryForObject("select failure_count from auth_account_attempts where account_id=?", Integer.class, user.getId())).isEqualTo(5);
        assertThat(jdbc.queryForObject("select count(*) from audit_events where target_id=? and action='LOGIN_FAILED'", Integer.class, user.getId())).isEqualTo(5);
        jdbc.update("update auth_account_attempts set window_started_at=?, last_attempt_at=?, blocked_until=? where account_id=?",
                java.sql.Timestamp.from(NOW.minusSeconds(301)), java.sql.Timestamp.from(NOW.minusSeconds(301)),
                java.sql.Timestamp.from(NOW.minusSeconds(1)), user.getId());
        assertThat(login.authenticate(user.getUsername(), PASSWORD).accepted()).isTrue();
        assertThat(jdbc.queryForObject("select failure_count from auth_account_attempts where account_id=?", Integer.class, user.getId())).isZero();
    }

    @Test void disabledUnknownAndExpiredTemporaryAccountsCannotGetSessions() {
        AppUser disabled = account("SELLER");
        disabled.setEnabled(false);
        users.saveAndFlush(disabled);
        assertThat(login.authenticate(disabled.getUsername(), PASSWORD).accepted()).isFalse();
        assertThat(login.authenticate("unknown_" + UUID.randomUUID().toString().replace("-", ""), PASSWORD).accepted()).isFalse();
        AppUser expired = account("SELLER");
        expired.setTemporaryPassword(passwords.encode(PASSWORD), NOW.minusSeconds(1));
        users.saveAndFlush(expired);
        assertThat(login.authenticate(expired.getUsername(), PASSWORD).accepted()).isFalse();
        AppUser temporary = account("SELLER");
        temporary.setTemporaryPassword(passwords.encode(PASSWORD), NOW.plusSeconds(60));
        users.saveAndFlush(temporary);
        var outcome = login.authenticate(temporary.getUsername(), PASSWORD);
        assertThat(outcome.accepted()).isTrue();
        assertThat(outcome.mustChangePassword()).isTrue();
        assertThat(sessions.authenticate(outcome.issued().token(), NOW.plusSeconds(60))).isEmpty();
    }

    @Test void simultaneousFailuresDoNotPassTheAccountLimit() throws Exception {
        AppUser user = account("SELLER");
        var start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(6)) {
            var futures = new ArrayList<java.util.concurrent.Future<Boolean>>();
            for (int i = 0; i < 6; i++) futures.add(executor.submit(() -> {
                if (!start.await(5, TimeUnit.SECONDS)) throw new IllegalStateException("Prazo excedido");
                return login.authenticate(user.getUsername(), "wrong-test-password").accepted();
            }));
            start.countDown();
            for (var result : futures) assertThat(result.get(15, TimeUnit.SECONDS)).isFalse();
        }
        assertThat(jdbc.queryForObject("select failure_count from auth_account_attempts where account_id=?", Integer.class, user.getId())).isEqualTo(5);
        assertThat(jdbc.queryForObject("select count(*) from audit_events where target_id=? and action='LOGIN_FAILED'", Integer.class, user.getId())).isEqualTo(5);
        assertThat(login.authenticate(user.getUsername(), PASSWORD).accepted()).isFalse();
    }

    private AppUser account(String role) {
        return users.saveAndFlush(new AppUser("login_" + UUID.randomUUID().toString().replace("-", ""), passwords.encode(PASSWORD), role));
    }
}
