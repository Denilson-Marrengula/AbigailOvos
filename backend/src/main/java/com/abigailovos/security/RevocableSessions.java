package com.abigailovos.security;

import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityNotFoundException;
import jakarta.persistence.LockModeType;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Optional;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Internal session storage used by the local session-only HTTP mode. The mode
 * is not validated for production. Callers must verify the password in the
 * same transaction before issuing.
 */
@Service
class RevocableSessions {
    private static final Duration CLOCK_SKEW = Duration.ofSeconds(5);
    private final EntityManager em;
    private final AppUserRepository users;
    private final Duration absoluteLifetime;
    private final Duration idleLifetime;
    private final SecureRandom random = new SecureRandom();

    RevocableSessions(EntityManager em, AppUserRepository users,
            @Value("${abigail.sessions.absolute-seconds:28800}") long absoluteSeconds,
            @Value("${abigail.sessions.idle-seconds:1800}") long idleSeconds) {
        if (absoluteSeconds < 60 || absoluteSeconds > 604800 || idleSeconds < 60 || idleSeconds > absoluteSeconds) {
            throw new IllegalArgumentException("Política de sessões inválida");
        }
        this.em = em;
        this.users = users;
        this.absoluteLifetime = Duration.ofSeconds(absoluteSeconds);
        this.idleLifetime = Duration.ofSeconds(idleSeconds);
    }

    record Issued(String token, Instant expiresAt) {
        @Override public String toString() { return "Issued[redacted]"; }
    }

    record Identity(String accountId, String username, String role, boolean mustChangePassword) {}
    private record Locked(AppUser account, RevocableSessionEntity session) {}

    /**
     * Only after verifying the password, while holding the
     * account write lock in the same transaction. This is not a login endpoint.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public Issued issueAfterVerifiedPassword(AppUser account, Instant now) {
        if (account == null || now == null || !em.contains(account)
                || em.getLockMode(account) != LockModeType.PESSIMISTIC_WRITE
                || !eligible(account, now)) {
            throw new IllegalStateException("Não foi possível criar a sessão.");
        }
        byte[] secret = new byte[32];
        random.nextBytes(secret);
        try {
            String token = Base64.getUrlEncoder().withoutPadding().encodeToString(secret);
            String hash = hashToken(token).orElseThrow();
            Instant expiresAt = now.plus(absoluteLifetime);
            em.persist(new RevocableSessionEntity(hash, account, now, expiresAt));
            return new Issued(token, expiresAt);
        } finally {
            java.util.Arrays.fill(secret, (byte) 0);
        }
    }

    /** A valid session is rechecked and touched under locks on each use. */
    @Transactional
    public Optional<Identity> authenticate(String token, Instant now) {
        if (now == null) return Optional.empty();
        Optional<Locked> locked = lock(token);
        if (locked.isEmpty()) return Optional.empty();
        AppUser account = locked.get().account();
        RevocableSessionEntity session = locked.get().session();
        if (session.accountEpoch() != account.sessionEpoch()
                || session.revokedAt() != null || now.isBefore(session.createdAt().minus(CLOCK_SKEW))
                || now.isBefore(session.lastSeenAt().minus(CLOCK_SKEW))) return Optional.empty();
        Instant effectiveNow = now.isBefore(session.lastSeenAt()) ? session.lastSeenAt() : now;
        if (!eligible(account, effectiveNow) || !session.expiresAt().isAfter(effectiveNow)
                || !session.lastSeenAt().plus(idleLifetime).isAfter(effectiveNow)) return Optional.empty();
        session.touch(effectiveNow);
        return Optional.of(new Identity(account.getId(), account.getUsername(), account.getRole(), account.mustChangePassword()));
    }

    /** Revoke one token. Changing passwords or account status invalidates all tokens through the account epoch. */
    @Transactional
    public void revoke(String token, Instant now) {
        if (now == null) return;
        lock(token).ifPresent(value -> value.session().revoke(now));
    }

    private Optional<Locked> lock(String token) {
        Optional<String> hash = hashToken(token);
        if (hash.isEmpty()) return Optional.empty();
        RevocableSessionEntity session = em.find(RevocableSessionEntity.class, hash.get());
        if (session == null) return Optional.empty();
        // Account first, then session: matches account deletion and avoids lock-order inversions.
        AppUser account = users.findForUpdate(session.accountId()).orElse(null);
        if (account == null) return Optional.empty();
        try {
            em.refresh(session, LockModeType.PESSIMISTIC_WRITE);
        } catch (EntityNotFoundException error) {
            return Optional.empty();
        }
        return Optional.of(new Locked(account, session));
    }

    private boolean eligible(AppUser account, Instant now) {
        return account.isEnabled() && (!account.mustChangePassword()
                || (account.temporaryPasswordExpiresAt() != null && account.temporaryPasswordExpiresAt().isAfter(now)));
    }

    private static Optional<String> hashToken(String token) {
        if (token == null || !token.matches("[A-Za-z0-9_-]{43}")) return Optional.empty();
        try {
            byte[] bytes = Base64.getUrlDecoder().decode(token);
            try {
                if (bytes.length != 32 || !Base64.getUrlEncoder().withoutPadding().encodeToString(bytes).equals(token)) {
                    return Optional.empty();
                }
                byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
                return Optional.of(HexFormat.of().formatHex(digest));
            } finally {
                java.util.Arrays.fill(bytes, (byte) 0);
            }
        } catch (IllegalArgumentException error) {
            return Optional.empty();
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException("Não foi possível verificar a sessão.");
        }
    }
}
