package com.abigailovos.security;

import com.abigailovos.audit.AuditLog;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import java.time.Clock;
import java.time.Instant;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Transactional login used by the unvalidated local session-only HTTP mode.
 * Per-account throttling is not an edge limiter and is insufficient on its own.
 * Proxy trust, recovery, TLS, CSRF and multi-instance behavior require validation
 * before exposing the system to real data.
 */
@Service
class SessionLogin {
    // Constant public test hash: used only to make unknown usernames perform bcrypt work.
    private static final String DUMMY_HASH = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy";
    private final EntityManager em;
    private final AppUserRepository users;
    private final PasswordEncoder passwords;
    private final RevocableSessions sessions;
    private final AuditLog audit;
    private final Clock clock;

    SessionLogin(EntityManager em, AppUserRepository users, PasswordEncoder passwords,
            RevocableSessions sessions, AuditLog audit, Clock clock) {
        this.em = em;
        this.users = users;
        this.passwords = passwords;
        this.sessions = sessions;
        this.audit = audit;
        this.clock = clock;
    }

    record Outcome(RevocableSessions.Issued issued, String username, String role, boolean mustChangePassword) {
        boolean accepted() { return issued != null; }
        @Override public String toString() { return "Outcome[redacted]"; }
        static Outcome denied() { return new Outcome(null, null, null, false); }
    }

    /** Caller must return rejected outcomes normally, not throw and roll back failure counters. */
    @Transactional
    public Outcome authenticate(String username, String password) {
        if (!validUsername(username) || !validPassword(password)) {
            burnBcrypt();
            return Outcome.denied();
        }
        AppUser snapshot = users.findByUsername(username).orElse(null);
        AppUser account = snapshot == null ? null : users.findForUpdate(snapshot.getId()).orElse(null);
        if (account == null) {
            burnBcrypt();
            return Outcome.denied();
        }
        // The earlier username lookup may have populated a stale managed entity.
        em.refresh(account, LockModeType.PESSIMISTIC_WRITE);
        if (!account.getUsername().equals(username)) {
            burnBcrypt();
            return Outcome.denied();
        }
        Instant now = clock.instant(); // measured after obtaining the account lock
        if (now == null || now.getEpochSecond() < 0) throw new IllegalStateException("Relógio inválido.");
        AccountAttemptEntity attempts = em.find(AccountAttemptEntity.class, account.getId());
        if (attempts != null) em.refresh(attempts, LockModeType.PESSIMISTIC_WRITE);

        // Always perform bcrypt for an existing account, including a blocked one.
        boolean passwordCorrect = passwords.matches(password, account.getPasswordHash());
        boolean eligible = account.isEnabled() && ("ADMIN".equals(account.getRole()) || "SELLER".equals(account.getRole()))
                && (!account.mustChangePassword() || (account.temporaryPasswordExpiresAt() != null
                        && account.temporaryPasswordExpiresAt().isAfter(now)));
        if (!eligible || (attempts != null && attempts.blocked(now))) return Outcome.denied();

        if (!passwordCorrect) {
            if (attempts == null) {
                attempts = new AccountAttemptEntity(account.getId(), now);
                em.persist(attempts);
            }
            attempts.failed(now);
            audit.record(account.getUsername(), "LOGIN_FAILED", "USER", account.getId(), "result=DENIED");
            return Outcome.denied();
        }

        RevocableSessions.Issued issued = sessions.issueAfterVerifiedPassword(account, now);
        if (attempts != null) attempts.reset(now);
        audit.record(account.getUsername(), "LOGIN_SUCCEEDED", "USER", account.getId(), "session=CREATED");
        return new Outcome(issued, account.getUsername(), account.getRole(), account.mustChangePassword());
    }

    private void burnBcrypt() { passwords.matches("unavailable-account", DUMMY_HASH); }
    private static boolean validUsername(String value) {
        return value != null && value.matches("[a-zA-Z0-9._-]{3,100}");
    }
    private static boolean validPassword(String value) {
        return value != null && value.matches("[\\x20-\\x7E]{1,72}");
    }
}
