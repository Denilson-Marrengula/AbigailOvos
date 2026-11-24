package com.abigailovos.security;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.Locale;

@Entity
@Table(name = "reserved_usernames")
class ReservedUsername {
    @Id @Column(name = "username_key", length = 100, updatable = false)
    private String usernameKey;
    @Column(name = "account_id", nullable = false, length = 36, updatable = false)
    private String accountId;
    @Column(name = "reserved_at", nullable = false, updatable = false)
    private Instant reservedAt;

    protected ReservedUsername() {}

    ReservedUsername(AppUser user) {
        usernameKey = key(user.getUsername());
        accountId = user.getId();
        reservedAt = Instant.now();
    }

    static String key(String username) { return username.toLowerCase(Locale.ROOT); }
    String accountId() { return accountId; }
}
