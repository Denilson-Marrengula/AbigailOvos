package com.abigailovos.security;

import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

class CredentialRedactionTest {
    @Test void credentialRecordsDoNotExposePasswordsOrTokensInToString() {
        var seller = new AccountController.CreateSeller("seller", "temporary-password-123", "Test", null);
        var change = new AccountController.ChangePassword("old-password-123", "new-password-123");
        var login = new SessionLoginController.Credentials("admin", "admin-password-123");
        var response = new SessionLoginController.LoginResponse("sensitive-token", Instant.EPOCH, "admin", List.of("ROLE_ADMIN"), false);
        assertThat(seller.toString()).doesNotContain("temporary-password-123");
        assertThat(change.toString()).doesNotContain("old-password-123", "new-password-123");
        assertThat(login.toString()).doesNotContain("admin-password-123");
        assertThat(response.toString()).doesNotContain("sensitive-token");
    }
}
