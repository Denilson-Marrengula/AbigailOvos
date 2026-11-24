package com.abigailovos.security;

import com.abigailovos.audit.AuditLog;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Arrays;
import java.util.Base64;
import java.util.OptionalLong;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Storage and atomic code consumption only. NOT an HTTP authentication service.
 * All mutations lock the account first; future login must consume the code and
 * issue the session in the same transaction, after verifying the password.
 */
@Service
class AdminAuthenticator {
    private static final Duration ENROLLMENT_LIFETIME = Duration.ofMinutes(15);
    private final EntityManager em;
    private final AppUserRepository users;
    private final AuditLog audit;
    private final String configuredKey;
    private final SecureRandom random = new SecureRandom();

    AdminAuthenticator(EntityManager em, AppUserRepository users, AuditLog audit,
            @Value("${ABIGAIL_MFA_KEY:}") String configuredKey) {
        this.em = em;
        this.users = users;
        this.audit = audit;
        this.configuredKey = configuredKey;
    }

    record Enrollment(String id, String secret, Instant expiresAt) {
        @Override public String toString() { return "Enrollment[redacted]"; }
    }

    /** Called only by the controlled non-web operator, never by password-only HTTP. */
    @Transactional
    public Enrollment stage(String accountId, boolean replacement, Instant now) {
        requireTime(now);
        AppUser account = lockAdmin(accountId);
        AdminAuthenticatorEntity entry = findLocked(account.getId());
        if (entry != null && entry.activeSecret() != null && !replacement) {
            throw new IllegalStateException("Já existe um autenticador; substituição não autorizada.");
        }
        if (replacement && (entry == null || entry.activeSecret() == null)) {
            throw new IllegalStateException("Não existe autenticador para substituir.");
        }
        byte[] key = key();
        byte[] secret = new byte[20];
        try {
            random.nextBytes(secret);
            String protectedSecret = Base64.getEncoder().encodeToString(
                    MfaSecretCipher.encrypt(key, account.getId(), secret, random));
            if (entry == null) {
                entry = new AdminAuthenticatorEntity(account.getId());
                em.persist(entry);
            }
            Instant expiry = now.plus(ENROLLMENT_LIFETIME);
            String id = UUID.randomUUID().toString();
            entry.stage(protectedSecret, id, now, expiry);
            audit.record("LOCAL_SECURITY_OPERATOR", "ADMIN_AUTHENTICATOR_STAGED", "USER", account.getId(),
                    replacement ? "mode=REPLACEMENT" : "mode=INITIAL");
            em.flush();
            return new Enrollment(id, AuthenticatorBase32.encode(secret), expiry);
        } finally {
            Arrays.fill(key, (byte) 0);
            Arrays.fill(secret, (byte) 0);
        }
    }

    /** Confirm locally before replacing an existing factor; invalid input changes nothing. */
    @Transactional
    public boolean confirm(String accountId, String enrollmentId, String code, Instant now) {
        requireTime(now);
        AppUser account = lockAdmin(accountId);
        AdminAuthenticatorEntity entry = findLocked(account.getId());
        if (entry == null || entry.pendingSecret() == null || entry.pendingId() == null
                || !entry.pendingId().equals(enrollmentId) || entry.pendingStartedAt() == null
                || entry.pendingExpiresAt() == null || now.isBefore(entry.pendingStartedAt())
                || !entry.pendingExpiresAt().isAfter(now)
                || entry.pendingExpiresAt().isAfter(entry.pendingStartedAt().plus(ENROLLMENT_LIFETIME))) return false;
        OptionalLong step = matching(entry.pendingSecret(), account.getId(), code, now, -1);
        if (step.isEmpty()) return false;
        boolean replacement = entry.activeSecret() != null;
        entry.activate(step.getAsLong());
        account.invalidateSessions();
        audit.record("LOCAL_SECURITY_OPERATOR", "ADMIN_AUTHENTICATOR_SET", "USER", account.getId(),
                replacement ? "mode=REPLACEMENT" : "mode=INITIAL");
        em.flush();
        return true;
    }

    /**
     * Requires the caller's transaction and an account freshly reloaded under a
     * write lock BEFORE password verification. No account mutations may be
     * pending. A rollback must roll back consumption and session issuance.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public boolean consumeForVerifiedPassword(AppUser account, String code, Instant now) {
        requireTime(now);
        if (account == null || !em.contains(account) || em.getLockMode(account) != LockModeType.PESSIMISTIC_WRITE) {
            throw new IllegalStateException("Não foi possível verificar o autenticador.");
        }
        em.refresh(account, LockModeType.PESSIMISTIC_WRITE);
        if (!account.isEnabled() || !"ADMIN".equals(account.getRole()))
            throw new IllegalStateException("Não foi possível verificar o autenticador.");
        AdminAuthenticatorEntity entry = findLocked(account.getId());
        if (entry == null || entry.activeSecret() == null
                || (entry.notBefore() != null && now.isBefore(entry.notBefore()))) return false;
        OptionalLong step = matching(entry.activeSecret(), account.getId(), code, now, entry.lastAcceptedStep());
        if (step.isEmpty()) return false;
        entry.accept(step.getAsLong());
        // A second check in the same transaction must not refresh an old step.
        em.flush();
        return true;
    }

    private AppUser lockAdmin(String accountId) {
        AppUser account = accountId == null ? null : users.findForUpdate(accountId).orElse(null);
        if (account == null || !account.isEnabled() || !"ADMIN".equals(account.getRole())) {
            throw new IllegalStateException("Conta administrativa indisponível.");
        }
        em.refresh(account, LockModeType.PESSIMISTIC_WRITE);
        if (!account.isEnabled() || !"ADMIN".equals(account.getRole()))
            throw new IllegalStateException("Conta administrativa indisponível.");
        return account;
    }

    private AdminAuthenticatorEntity findLocked(String accountId) {
        AdminAuthenticatorEntity entry = em.find(AdminAuthenticatorEntity.class, accountId);
        if (entry != null) em.refresh(entry, LockModeType.PESSIMISTIC_WRITE);
        return entry;
    }

    private OptionalLong matching(String encrypted, String accountId, String code, Instant now, long lastStep) {
        byte[] key = key();
        byte[] secret = null;
        try {
            byte[] envelope = Base64.getDecoder().decode(encrypted);
            secret = MfaSecretCipher.decrypt(key, accountId, envelope);
            return TotpCodes.matchingStep(secret, code, now, lastStep);
        } catch (IllegalArgumentException error) {
            throw new IllegalStateException("Não foi possível verificar o autenticador.");
        } finally {
            Arrays.fill(key, (byte) 0);
            if (secret != null) Arrays.fill(secret, (byte) 0);
        }
    }

    private byte[] key() {
        try {
            byte[] key = Base64.getDecoder().decode(configuredKey);
            if (key.length == 32 && Base64.getEncoder().encodeToString(key).equals(configuredKey)) return key;
            Arrays.fill(key, (byte) 0);
        } catch (IllegalArgumentException ignored) {
            // Do not expose configuration contents in the error.
        }
        throw new IllegalStateException("Chave do autenticador indisponível ou inválida.");
    }

    private static void requireTime(Instant now) {
        if (now == null || now.getEpochSecond() < 0) throw new IllegalArgumentException("Relógio inválido.");
    }
}
