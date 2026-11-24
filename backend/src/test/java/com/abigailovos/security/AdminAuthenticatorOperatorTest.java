package com.abigailovos.security;

import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.test.context.runner.WebApplicationContextRunner;
import org.springframework.mock.env.MockEnvironment;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Prepared safety checks for the local operator; no real terminal or database. */
class AdminAuthenticatorOperatorTest {
    private final AppUserRepository users = mock(AppUserRepository.class);
    private final AdminAuthenticator mfa = mock(AdminAuthenticator.class);
    private static final String[] SAFE = {
        "abigail.mfa-operator.enabled=true", "spring.main.web-application-type=none",
        "spring.flyway.enabled=false", "spring.jpa.hibernate.ddl-auto=validate", "spring.sql.init.mode=never"
    };

    @Test void requiresAnInteractiveConsoleBeforeAccessingAccounts() {
        var environment = new MockEnvironment().withProperty("spring.main.web-application-type", "none")
                .withProperty("spring.flyway.enabled", "false").withProperty("spring.jpa.hibernate.ddl-auto", "validate")
                .withProperty("spring.sql.init.mode", "never");
        assertThatThrownBy(() -> AdminAuthenticatorOperator.operate(environment, users, mfa, null))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("terminal interativo");
        verifyNoInteractions(users, mfa);
    }

    @Test void rejectsSchemaChangingSettingsBeforeRegularBeansStart() {
        for (String invalid : new String[] { "spring.flyway.enabled=true", "spring.jpa.hibernate.ddl-auto=update",
                "spring.sql.init.mode=always", "abigail.bootstrap.enabled=true", "spring.main.web-application-type=servlet",
                "abigail.admin-password-operator.enabled=true", "abigail.restore-session-operator.enabled=true",
                "abigail.security.session-mode=false" }) {
            var started = new AtomicBoolean();
            runner(started).withPropertyValues(SAFE).withPropertyValues(invalid).run(context -> {
                assertThat(context).hasFailed();
                assertThat(started).isFalse();
            });
        }
    }

    @Test void rejectsActualWebContextEvenWhenPropertyClaimsNonWeb() {
        var started = new AtomicBoolean();
        new WebApplicationContextRunner().withUserConfiguration(AdminAuthenticatorOperator.class)
                .withBean(AppUserRepository.class, () -> users).withBean(AdminAuthenticator.class, () -> mfa)
                .withBean("probe", Object.class, () -> { started.set(true); return new Object(); })
                .withPropertyValues(SAFE).run(context -> {
                    assertThat(context).hasFailed();
                    assertThat(started).isFalse();
                });
    }

    @Test void legacyOperatorIsRefusedEvenInNonWebConfiguration() {
        var started = new AtomicBoolean();
        runner(started).withPropertyValues(SAFE).run(context -> {
            assertThat(context).hasFailed();
            assertThat(started).isFalse();
            verifyNoInteractions(users, mfa);
        });
    }

    private ApplicationContextRunner runner(AtomicBoolean started) {
        return new ApplicationContextRunner().withUserConfiguration(AdminAuthenticatorOperator.class)
                .withBean(AppUserRepository.class, () -> users).withBean(AdminAuthenticator.class, () -> mfa)
                .withBean("probe", Object.class, () -> { started.set(true); return new Object(); });
    }
}
