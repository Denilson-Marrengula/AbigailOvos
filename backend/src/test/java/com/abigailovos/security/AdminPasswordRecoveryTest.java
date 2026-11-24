package com.abigailovos.security;

import java.time.Clock;
import java.time.Instant;
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
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;

/** Internal recovery tests only; the active user identity is verified operationally. */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:admin_password_recovery;MODE=MySQL;DB_CLOSE_DELAY=-1",
        "ABIGAIL_MFA_KEY=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
})
@Import(AdminPasswordRecoveryTest.FixedClock.class)
class AdminPasswordRecoveryTest {
    private static final Instant NOW = Instant.parse("2026-11-15T10:00:00Z");
    private static final String OLD_PASSWORD = "old-test-password";
    @Autowired AdminPasswordRecovery recovery;
    @Autowired AdminAuthenticator mfa;
    @Autowired SessionLogin login;
    @Autowired AppUserRepository users;
    @Autowired PasswordEncoder passwords;
    @Autowired RevocableSessions sessions;
    @Autowired TransactionTemplate transactions;
    @Autowired JdbcTemplate jdbc;

    @TestConfiguration(proxyBeanMethods = false)
    static class FixedClock {
        @Bean @Primary Clock recoveryClock() { return Clock.fixed(NOW, ZoneOffset.UTC); }
    }

    @Test void resetsPasswordRevokesSessionsAndPreservesHistoricalAuthenticator() {
        AppUser admin = account("ADMIN");
        var enrollment = AdminAuthenticatorTest.stageWithDistinctNext(mfa, admin, NOW);
        byte[] factor = AdminAuthenticatorTest.decode(enrollment.secret());
        char[] temporary = "temporary-test-password".toCharArray();
        try {
            String initial = TotpCodes.generate(factor, NOW.getEpochSecond() / 30, 6);
            assertThat(mfa.confirm(admin.getId(), enrollment.id(), initial, NOW)).isTrue();
            String stored = jdbc.queryForObject("select active_secret from admin_authenticators where account_id=?", String.class, admin.getId());
            var oldSession = transactions.execute(status -> sessions.issueAfterVerifiedPassword(
                    users.findForUpdate(admin.getId()).orElseThrow(), NOW));
            Instant expiry = recovery.reset(admin.getId(), temporary);
            assertThat(expiry).isEqualTo(NOW.plusSeconds(24 * 3600));
            assertThat(sessions.authenticate(oldSession.token(), NOW)).isEmpty();
            AppUser updated = users.findById(admin.getId()).orElseThrow();
            assertThat(updated.mustChangePassword()).isTrue();
            assertThat(passwords.matches(OLD_PASSWORD, updated.getPasswordHash())).isFalse();
            assertThat(passwords.matches(new String(temporary), updated.getPasswordHash())).isTrue();
            var result = login.authenticate(admin.getUsername(), new String(temporary));
            assertThat(result.accepted()).isTrue();
            assertThat(result.mustChangePassword()).isTrue();
            assertThat(jdbc.queryForObject("select active_secret from admin_authenticators where account_id=?", String.class, admin.getId())).isEqualTo(stored);
            assertThat(jdbc.queryForObject("select count(*) from audit_events where target_id=? and action='ADMIN_PASSWORD_RESET'", Integer.class, admin.getId())).isEqualTo(1);
            assertThat(jdbc.queryForObject("select detail from audit_events where target_id=? and action='ADMIN_PASSWORD_RESET'", String.class, admin.getId()))
                    .doesNotContain(new String(temporary));
        } finally {
            Arrays.fill(factor, (byte) 0);
            Arrays.fill(temporary, '\0');
        }
    }

    @Test void refusesInvalidSameDisabledAndNonAdminAccounts() {
        AppUser admin = account("ADMIN");
        AppUser seller = account("SELLER");
        AppUser disabled = account("ADMIN");
        disabled.setEnabled(false);
        users.saveAndFlush(disabled);
        assertThatThrownBy(() -> recovery.reset(admin.getId(), "short".toCharArray())).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> recovery.reset(admin.getId(), OLD_PASSWORD.toCharArray())).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> recovery.reset(seller.getId(), "temporary-test-password".toCharArray())).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> recovery.reset(disabled.getId(), "temporary-test-password".toCharArray())).isInstanceOf(IllegalStateException.class);
        assertThat(passwords.matches(OLD_PASSWORD, users.findById(admin.getId()).orElseThrow().getPasswordHash())).isTrue();
    }

    private AppUser account(String role) {
        return users.saveAndFlush(new AppUser("recover_" + UUID.randomUUID().toString().replace("-", ""), passwords.encode(OLD_PASSWORD), role));
    }
}
