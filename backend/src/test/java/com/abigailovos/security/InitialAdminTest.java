package com.abigailovos.security;

import org.junit.jupiter.api.Test;
import com.abigailovos.AbigailOvosApplication;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class InitialAdminTest {
    private final AppUserRepository users = mock(AppUserRepository.class);
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();
    private final InitialAdmin.AdminProvisioner provisioner = new InitialAdmin.AdminProvisioner(users, encoder);

    @Test
    void createsOnlyAdminWithHashedPassword() {
        provisioner.provision("admin.example", "test-password-123", null, null);
        var captor = org.mockito.ArgumentCaptor.forClass(AppUser.class);
        verify(users).saveAndFlush(captor.capture());
        assertThat(captor.getValue().getRole()).isEqualTo("ADMIN");
        assertThat(encoder.matches("test-password-123", captor.getValue().getPasswordHash())).isTrue();
    }

    @Test
    void refusesExistingAccountsAndInvalidCredentials() {
        when(users.count()).thenReturn(1L);
        assertThatThrownBy(() -> provisioner.provision("admin", "test-password-123", null, null))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> provisioner.provision("admin", "short", null, null))
                .isInstanceOf(IllegalStateException.class);
        verify(users, never()).saveAndFlush(any());
    }

    @Test
    void nonWebBootstrapStartsAndPersistsAdmin() {
        try (var context = new SpringApplicationBuilder(AbigailOvosApplication.class)
                .run("--spring.main.web-application-type=none",
                     "--spring.datasource.url=jdbc:h2:mem:bootstrap;DB_CLOSE_DELAY=-1",
                     "--spring.datasource.username=sa", "--spring.datasource.password=",
                     "--spring.jpa.hibernate.ddl-auto=create-drop", "--spring.flyway.enabled=false",
                     "--abigail.bootstrap.enabled=true", "--abigail.bootstrap.username=admin",
                     "--abigail.bootstrap.password=test-password-123",
                     "--abigail.bootstrap.seller-username=vendedor",
                     "--abigail.bootstrap.seller-password=other-test-password")) {
            var user = context.getBean(AppUserRepository.class).findByUsername("admin").orElseThrow();
            assertThat(user.getRole()).isEqualTo("ADMIN");
            assertThat(encoder.matches("test-password-123", user.getPasswordHash())).isTrue();
            var seller = context.getBean(AppUserRepository.class).findByUsername("vendedor").orElseThrow();
            assertThat(seller.getRole()).isEqualTo("SELLER");
            assertThat(encoder.matches("other-test-password", seller.getPasswordHash())).isTrue();
        }
    }
}
