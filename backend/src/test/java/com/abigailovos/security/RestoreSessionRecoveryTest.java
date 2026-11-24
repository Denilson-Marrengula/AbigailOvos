package com.abigailovos.security;

import java.time.Instant;
import java.time.Clock;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.UUID;
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

/** Only synthetic H2 storage; no backup or database restore is performed. */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:restore_sessions;MODE=MySQL;DB_CLOSE_DELAY=-1",
        "ABIGAIL_MFA_KEY=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
})
@Import(RestoreSessionRecoveryTest.FixedClock.class)
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_EACH_TEST_METHOD)
class RestoreSessionRecoveryTest {
    private static final Instant NOW = Instant.parse("2026-11-15T10:00:00Z");
    @Autowired RestoreSessionRecovery recovery;
    @Autowired AdminAuthenticator mfa;
    @Autowired RevocableSessions sessions;
    @Autowired AppUserRepository users;
    @Autowired TransactionTemplate transactions;
    @Autowired JdbcTemplate jdbc;

    @TestConfiguration(proxyBeanMethods = false)
    static class FixedClock {
        @Bean @Primary Clock restoreClock() { return Clock.fixed(NOW, ZoneOffset.UTC); }
    }

    @Test void invalidatesEveryRestoredSessionWithoutDeletingHistory() {
        AppUser admin = account("ADMIN");
        AppUser seller = account("SELLER");
        var first = issue(admin);
        var second = issue(seller);
        assertThat(sessions.authenticate(first.token(), NOW)).isPresent();
        assertThat(sessions.authenticate(second.token(), NOW)).isPresent();
        assertThat(recovery.invalidateAll()).isEqualTo(2);
        assertThat(sessions.authenticate(first.token(), NOW)).isEmpty();
        assertThat(sessions.authenticate(second.token(), NOW)).isEmpty();
        assertThat(users.findById(admin.getId()).orElseThrow().getPasswordHash()).isEqualTo("test-hash");
        assertThat(users.findById(seller.getId()).orElseThrow().getPasswordHash()).isEqualTo("test-hash");
        assertThat(jdbc.queryForObject("select count(*) from auth_sessions", Integer.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject("select count(*) from audit_events where action='RESTORED_SESSIONS_INVALIDATED'", Integer.class)).isEqualTo(1);
    }

    @Test void overflowRollsBackTheWholeOperation() {
        AppUser first = account("ADMIN");
        AppUser other = account("SELLER");
        jdbc.update("update app_users set session_epoch=? where id=?", Long.MAX_VALUE, first.getId());
        assertThatThrownBy(recovery::invalidateAll).isInstanceOf(IllegalStateException.class);
        assertThat(users.findById(other.getId()).orElseThrow().sessionEpoch()).isZero();
        assertThat(jdbc.queryForObject("select count(*) from audit_events where action='RESTORED_SESSIONS_INVALIDATED'", Integer.class)).isZero();
    }

    @Test void refusesAnEmptyRestoredDatabase() {
        assertThatThrownBy(recovery::invalidateAll).isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Nenhuma conta");
        assertThat(jdbc.queryForObject("select count(*) from audit_events where action='RESTORED_SESSIONS_INVALIDATED'", Integer.class)).isZero();
    }

    @Test void preservesHistoricalAuthenticatorDataWhenInvalidatingSessions() {
        AppUser admin = account("ADMIN");
        var enrollment = AdminAuthenticatorTest.stageWithDistinctNext(mfa, admin, NOW);
        byte[] secret = AdminAuthenticatorTest.decode(enrollment.secret());
        try {
            String initial = TotpCodes.generate(secret, NOW.getEpochSecond() / 30, 6);
            assertThat(mfa.confirm(admin.getId(), enrollment.id(), initial, NOW)).isTrue();
            String stored = jdbc.queryForObject("select active_secret from admin_authenticators where account_id=?", String.class, admin.getId());
            Long step = jdbc.queryForObject("select last_accepted_step from admin_authenticators where account_id=?", Long.class, admin.getId());
            recovery.invalidateAll();
            assertThat(jdbc.queryForObject("select active_secret from admin_authenticators where account_id=?", String.class, admin.getId())).isEqualTo(stored);
            assertThat(jdbc.queryForObject("select last_accepted_step from admin_authenticators where account_id=?", Long.class, admin.getId())).isEqualTo(step);
            assertThat(jdbc.queryForObject("select not_before from admin_authenticators where account_id=?", java.sql.Timestamp.class, admin.getId())).isNull();
        } finally { Arrays.fill(secret, (byte) 0); }
    }

    private AppUser account(String role) {
        return users.saveAndFlush(new AppUser("restore_" + UUID.randomUUID().toString().replace("-", ""), "test-hash", role));
    }
    private RevocableSessions.Issued issue(AppUser user) {
        return transactions.execute(status -> sessions.issueAfterVerifiedPassword(users.findForUpdate(user.getId()).orElseThrow(), NOW));
    }
}
