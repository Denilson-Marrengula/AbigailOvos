package com.abigailovos.security;

import com.abigailovos.audit.AuditLog;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import java.nio.CharBuffer;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Privileged non-web operator only. No public or password-only recovery endpoint. */
@Service
class AdminPasswordRecovery {
    private final AppUserRepository users;
    private final EntityManager em;
    private final PasswordEncoder passwords;
    private final AuditLog audit;
    private final Clock clock;

    AdminPasswordRecovery(AppUserRepository users, EntityManager em, PasswordEncoder passwords, AuditLog audit, Clock clock) {
        this.users = users;
        this.em = em;
        this.passwords = passwords;
        this.audit = audit;
        this.clock = clock;
    }

    @Transactional
    public Instant reset(String accountId, char[] temporaryPassword) {
        if (!valid(temporaryPassword)) throw new IllegalArgumentException("Palavra-passe temporária inválida.");
        AppUser user = accountId == null ? null : users.findForUpdate(accountId).orElse(null);
        if (user == null) throw new IllegalStateException("Conta administrativa indisponível.");
        em.refresh(user, LockModeType.PESSIMISTIC_WRITE);
        if (!user.isEnabled() || !"ADMIN".equals(user.getRole())) throw new IllegalStateException("Conta administrativa indisponível.");
        CharBuffer secret = CharBuffer.wrap(temporaryPassword);
        if (passwords.matches(secret, user.getPasswordHash())) throw new IllegalArgumentException("Escolha uma palavra-passe diferente.");
        Instant now = clock.instant();
        if (now == null || now.getEpochSecond() < 0) throw new IllegalStateException("Relógio inválido.");
        Instant expires = now.plus(Duration.ofHours(24));
        user.setTemporaryPassword(passwords.encode(secret), expires);
        audit.record("LOCAL_SECURITY_OPERATOR", "ADMIN_PASSWORD_RESET", "USER", user.getId(), "temporary=true");
        return expires;
    }

    private static boolean valid(char[] value) {
        if (value == null || value.length < 12 || value.length > 72) return false;
        boolean nonSpace = false;
        for (char c : value) {
            if (c < 0x20 || c > 0x7e) return false;
            if (c != ' ') nonSpace = true;
        }
        return nonSpace;
    }
}
