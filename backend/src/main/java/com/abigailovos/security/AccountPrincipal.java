package com.abigailovos.security;

import java.time.Instant;
import java.util.List;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.User;

/** Authentication state is reloaded from the database for each Basic request. */
final class AccountPrincipal extends User {
    private final boolean mustChangePassword;

    AccountPrincipal(AppUser account) {
        super(account.getUsername(), account.getPasswordHash(), account.isEnabled(), true,
                !account.mustChangePassword() || (account.temporaryPasswordExpiresAt() != null
                        && account.temporaryPasswordExpiresAt().isAfter(Instant.now())),
                true, List.of(new SimpleGrantedAuthority("ROLE_" + account.getRole())));
        this.mustChangePassword = account.mustChangePassword();
    }

    boolean mustChangePassword() { return mustChangePassword; }
}
