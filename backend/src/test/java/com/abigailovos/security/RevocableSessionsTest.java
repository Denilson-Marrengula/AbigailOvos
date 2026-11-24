package com.abigailovos.security;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;

/** Exercises storage only. No HTTP authentication uses these sessions yet. */
@SpringBootTest(properties = "spring.datasource.url=jdbc:h2:mem:revocable_sessions;MODE=MySQL;DB_CLOSE_DELAY=-1")
class RevocableSessionsTest {
    @Autowired RevocableSessions sessions;
    @Autowired AppUserRepository users;
    @Autowired TransactionTemplate transactions;
    @Autowired JdbcTemplate jdbc;
    private static final Instant NOW = Instant.parse("2026-11-14T10:00:00Z");

    @Test void storesOnlyTheDigestAndRevokesEachTokenIndependently() throws Exception {
        AppUser user = account();
        var first = issue(user, NOW);
        var second = issue(user, NOW);
        assertThat(first.token()).hasSize(43).isNotEqualTo(second.token());
        assertThat(first.toString()).doesNotContain(first.token());
        String digest = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Base64.getUrlDecoder().decode(first.token())));
        assertThat(jdbc.queryForObject("select count(*) from auth_sessions where token_hash = ? and account_id = ?", Integer.class, digest, user.getId())).isEqualTo(1);
        assertThat(jdbc.queryForObject("select count(*) from auth_sessions where token_hash = ?", Integer.class, first.token())).isZero();
        assertThat(sessions.authenticate(first.token(), NOW).orElseThrow().username()).isEqualTo(user.getUsername());
        sessions.revoke(first.token(), NOW.plusSeconds(1));
        assertThat(sessions.authenticate(first.token(), NOW.plusSeconds(2))).isEmpty();
        assertThat(sessions.authenticate(second.token(), NOW.plusSeconds(2))).isPresent();
        assertThat(sessions.authenticate("not-a-valid-token", NOW)).isEmpty();
        assertThat(sessions.authenticate(Base64.getUrlEncoder().withoutPadding().encodeToString("short".getBytes(StandardCharsets.US_ASCII)), NOW)).isEmpty();
    }

    @Test void expiresOnIdleOrAbsoluteDeadline() {
        AppUser user = account();
        var idle = issue(user, NOW);
        assertThat(sessions.authenticate(idle.token(), NOW.plusSeconds(1799))).isPresent();
        assertThat(sessions.authenticate(idle.token(), NOW.plusSeconds(3599))).isEmpty();
        var absolute = issue(user, NOW);
        for (int minutes = 20; minutes < 480; minutes += 20) {
            assertThat(sessions.authenticate(absolute.token(), NOW.plusSeconds(minutes * 60L))).isPresent();
        }
        assertThat(sessions.authenticate(absolute.token(), NOW.plusSeconds(8 * 3600L))).isEmpty();
        assertThat(sessions.authenticate(absolute.token(), NOW.minusSeconds(6))).isEmpty();
    }

    @Test void accountChangesAndDeletionInvalidateExistingTokens() {
        AppUser user = account();
        var original = issue(user, NOW);
        transactions.executeWithoutResult(status -> users.findForUpdate(user.getId()).orElseThrow()
                .setTemporaryPassword("hash-temporario", NOW.plusSeconds(3600)));
        assertThat(sessions.authenticate(original.token(), NOW.plusSeconds(1))).isEmpty();
        var temporary = issue(user, NOW.plusSeconds(1));
        assertThat(sessions.authenticate(temporary.token(), NOW.plusSeconds(2)).orElseThrow().mustChangePassword()).isTrue();
        transactions.executeWithoutResult(status -> users.findForUpdate(user.getId()).orElseThrow().changePassword("hash-novo"));
        assertThat(sessions.authenticate(temporary.token(), NOW.plusSeconds(3))).isEmpty();
        var afterChange = issue(user, NOW.plusSeconds(4));
        transactions.executeWithoutResult(status -> users.findForUpdate(user.getId()).orElseThrow().setEnabled(false));
        assertThat(sessions.authenticate(afterChange.token(), NOW.plusSeconds(5))).isEmpty();
        transactions.executeWithoutResult(status -> users.findForUpdate(user.getId()).orElseThrow().setEnabled(true));
        assertThat(sessions.authenticate(afterChange.token(), NOW.plusSeconds(6))).isEmpty();
        var afterReactivation = issue(user, NOW.plusSeconds(7));
        transactions.executeWithoutResult(status -> users.delete(users.findForUpdate(user.getId()).orElseThrow()));
        assertThat(sessions.authenticate(afterReactivation.token(), NOW.plusSeconds(8))).isEmpty();
    }

    @Test void willNotIssueWithoutAnAccountWriteLock() {
        AppUser user = account();
        assertThatThrownBy(() -> transactions.execute(status ->
                sessions.issueAfterVerifiedPassword(users.findById(user.getId()).orElseThrow(), NOW)))
                .isInstanceOf(IllegalStateException.class);
    }

    private AppUser account() {
        return users.saveAndFlush(new AppUser("session_" + UUID.randomUUID().toString().replace("-", ""), "hash-teste", "SELLER"));
    }

    private RevocableSessions.Issued issue(AppUser user, Instant now) {
        return transactions.execute(status -> sessions.issueAfterVerifiedPassword(users.findForUpdate(user.getId()).orElseThrow(), now));
    }
}
