package com.abigailovos.security;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;

/** Storage/locking tests only: these methods are not connected to HTTP. */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:admin_authenticator;MODE=MySQL;DB_CLOSE_DELAY=-1",
        "ABIGAIL_MFA_KEY=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
})
class AdminAuthenticatorTest {
    @Autowired AdminAuthenticator authenticators;
    @Autowired AppUserRepository users;
    @Autowired TransactionTemplate transactions;
    @Autowired RevocableSessions sessions;
    @Autowired JdbcTemplate jdbc;
    private static final Instant NOW = Instant.parse("2026-11-14T10:00:00Z");

    @Test void base32UsesTheStandardUnpaddedAlphabet() {
        assertThat(AuthenticatorBase32.encode(new byte[0])).isEmpty();
        assertThat(AuthenticatorBase32.encode("f".getBytes(java.nio.charset.StandardCharsets.US_ASCII))).isEqualTo("MY");
        assertThat(AuthenticatorBase32.encode("foobar".getBytes(java.nio.charset.StandardCharsets.US_ASCII))).isEqualTo("MZXW6YTBOI");
    }

    @Test void enrollsOnlyAnAdminAndConsumesEachStepOnce() {
        AppUser admin = account("ADMIN");
        AppUser seller = account("SELLER");
        assertThatThrownBy(() -> authenticators.stage(seller.getId(), false, NOW))
                .isInstanceOf(IllegalStateException.class);
        var enrollment = stageWithDistinctNext(authenticators, admin, NOW);
        assertThat(enrollment.toString()).doesNotContain(enrollment.secret()).doesNotContain(enrollment.id());
        byte[] secret = decode(enrollment.secret());
        String code = TotpCodes.generate(secret, NOW.getEpochSecond() / 30, 6);
        assertThat(authenticators.confirm(admin.getId(), "wrong-id", code, NOW)).isFalse();
        assertThat(authenticators.confirm(admin.getId(), enrollment.id(), "invalid", NOW)).isFalse();
        assertThat(authenticators.confirm(admin.getId(), enrollment.id(), code, NOW.minusSeconds(1))).isFalse();
        assertThat(authenticators.confirm(admin.getId(), enrollment.id(), code, NOW)).isTrue();
        String stored = jdbc.queryForObject("select active_secret from admin_authenticators where account_id=?", String.class, admin.getId());
        assertThat(stored).isNotBlank().doesNotContain(enrollment.secret());
        assertThat(jdbc.queryForObject("select pending_secret from admin_authenticators where account_id=?", String.class, admin.getId())).isNull();
        assertThat(consume(admin, code, NOW)).isFalse(); // confirmation already consumed this step
        Instant next = NOW.plusSeconds(30);
        String nextCode = TotpCodes.generate(secret, next.getEpochSecond() / 30, 6);
        assertThat(consume(admin, nextCode, next)).isTrue();
        assertThat(consume(admin, nextCode, next)).isFalse();
        assertThat(jdbc.queryForObject("select count(*) from audit_events where target_id=? and action='ADMIN_AUTHENTICATOR_SET'", Integer.class, admin.getId())).isEqualTo(1);
        Arrays.fill(secret, (byte) 0);
    }

    @Test void replacementRequiresConfirmationAndInvalidatesExistingSessions() {
        AppUser admin = account("ADMIN");
        var first = authenticators.stage(admin.getId(), false, NOW);
        byte[] oldSecret = decode(first.secret());
        assertThat(authenticators.confirm(admin.getId(), first.id(), code(oldSecret, NOW), NOW)).isTrue();
        var session = transactions.execute(status -> sessions.issueAfterVerifiedPassword(users.findForUpdate(admin.getId()).orElseThrow(), NOW));
        assertThatThrownBy(() -> authenticators.stage(admin.getId(), false, NOW.plusSeconds(1)))
                .isInstanceOf(IllegalStateException.class);
        var replacement = authenticators.stage(admin.getId(), true, NOW.plusSeconds(1));
        assertThat(sessions.authenticate(session.token(), NOW.plusSeconds(2))).isPresent();
        byte[] newSecret = decode(replacement.secret());
        assertThat(authenticators.confirm(admin.getId(), replacement.id(), code(newSecret, NOW), NOW.plusSeconds(901))).isFalse();
        assertThat(sessions.authenticate(session.token(), NOW.plusSeconds(3))).isPresent();
        var retry = authenticators.stage(admin.getId(), true, NOW.plusSeconds(4));
        byte[] retrySecret = decode(retry.secret());
        assertThat(authenticators.confirm(admin.getId(), replacement.id(), code(newSecret, NOW), NOW.plusSeconds(5))).isFalse();
        assertThat(authenticators.confirm(admin.getId(), retry.id(), code(retrySecret, NOW), NOW.plusSeconds(5))).isTrue();
        assertThat(sessions.authenticate(session.token(), NOW.plusSeconds(6))).isEmpty();
        Arrays.fill(oldSecret, (byte) 0);
        Arrays.fill(newSecret, (byte) 0);
        Arrays.fill(retrySecret, (byte) 0);
    }

    @Test void rollbackDoesNotConsumeTheCode() {
        AppUser admin = account("ADMIN");
        var enrollment = stageWithDistinctNext(authenticators, admin, NOW);
        byte[] secret = decode(enrollment.secret());
        assertThat(authenticators.confirm(admin.getId(), enrollment.id(), code(secret, NOW), NOW)).isTrue();
        Instant next = NOW.plusSeconds(30);
        String value = code(secret, next);
        Boolean acceptedBeforeRollback = transactions.execute(status -> {
            boolean accepted = authenticators.consumeForVerifiedPassword(users.findForUpdate(admin.getId()).orElseThrow(), value, next);
            status.setRollbackOnly();
            return accepted;
        });
        assertThat(acceptedBeforeRollback).isTrue();
        assertThat(consume(admin, value, next)).isTrue();
        Arrays.fill(secret, (byte) 0);
    }

    @Test void twoChecksInOneTransactionCannotReuseACode() {
        AppUser admin = account("ADMIN");
        var enrollment = stageWithDistinctNext(authenticators, admin, NOW);
        byte[] secret = decode(enrollment.secret());
        assertThat(authenticators.confirm(admin.getId(), enrollment.id(), code(secret, NOW), NOW)).isTrue();
        Instant next = NOW.plusSeconds(30);
        String value = code(secret, next);
        List<Boolean> results = transactions.execute(status -> {
            AppUser locked = users.findForUpdate(admin.getId()).orElseThrow();
            return List.of(authenticators.consumeForVerifiedPassword(locked, value, next),
                    authenticators.consumeForVerifiedPassword(locked, value, next));
        });
        assertThat(results).containsExactly(true, false);
        Arrays.fill(secret, (byte) 0);
    }

    @Test void concurrentSubmissionsCanConsumeOnlyOnce() throws Exception {
        AppUser admin = account("ADMIN");
        var enrollment = stageWithDistinctNext(authenticators, admin, NOW);
        byte[] secret = decode(enrollment.secret());
        assertThat(authenticators.confirm(admin.getId(), enrollment.id(), code(secret, NOW), NOW)).isTrue();
        Instant next = NOW.plusSeconds(30);
        String value = code(secret, next);
        var ready = new CountDownLatch(2);
        var start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(2)) {
            List<java.util.concurrent.Future<Boolean>> futures = new ArrayList<>();
            for (int i = 0; i < 2; i++) {
                futures.add(executor.submit(() -> {
                    ready.countDown();
                    if (!start.await(5, TimeUnit.SECONDS)) throw new IllegalStateException("Teste excedeu o prazo");
                    return consume(admin, value, next);
                }));
            }
            assertThat(ready.await(5, TimeUnit.SECONDS)).isTrue();
            start.countDown();
            assertThat(List.of(futures.get(0).get(10, TimeUnit.SECONDS), futures.get(1).get(10, TimeUnit.SECONDS)))
                    .containsExactlyInAnyOrder(true, false);
        } finally { Arrays.fill(secret, (byte) 0); }
    }

    @Test void refusesConsumptionWithoutAWriteLock() {
        AppUser admin = account("ADMIN");
        assertThatThrownBy(() -> transactions.execute(status -> authenticators.consumeForVerifiedPassword(
                users.findById(admin.getId()).orElseThrow(), "123456", NOW))).isInstanceOf(IllegalStateException.class);
    }

    private AppUser account(String role) {
        return users.saveAndFlush(new AppUser("mfa_" + UUID.randomUUID().toString().replace("-", ""), "hash-teste", role));
    }

    private boolean consume(AppUser admin, String value, Instant now) {
        return Boolean.TRUE.equals(transactions.execute(status -> authenticators.consumeForVerifiedPassword(
                users.findForUpdate(admin.getId()).orElseThrow(), value, now)));
    }

    private static String code(byte[] secret, Instant now) {
        return TotpCodes.generate(secret, now.getEpochSecond() / 30, 6);
    }

    /** Random TOTP secrets can produce equal adjacent codes; avoid a flaky fixture. */
    static AdminAuthenticator.Enrollment stageWithDistinctNext(AdminAuthenticator mfa, AppUser admin, Instant now) {
        for (int i = 0; i < 16; i++) {
            var enrollment = mfa.stage(admin.getId(), false, now);
            byte[] secret = decode(enrollment.secret());
            try {
                if (!code(secret, now).equals(code(secret, now.plusSeconds(30)))) return enrollment;
            } finally { Arrays.fill(secret, (byte) 0); }
        }
        throw new AssertionError("Não foi possível preparar códigos de teste distintos.");
    }

    static byte[] decode(String value) {
        byte[] output = new byte[value.length() * 5 / 8];
        String alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
        int buffer = 0, bits = 0, index = 0;
        for (char c : value.toCharArray()) {
            int digit = alphabet.indexOf(c);
            if (digit < 0) throw new IllegalArgumentException();
            buffer = (buffer << 5) | digit;
            bits += 5;
            if (bits >= 8) {
                bits -= 8;
                output[index++] = (byte) (buffer >>> bits);
            }
        }
        return output;
    }
}
