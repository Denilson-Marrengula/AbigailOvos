package com.abigailovos.security;

import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.test.context.runner.WebApplicationContextRunner;
import org.springframework.mock.env.MockEnvironment;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class AdminPasswordOperatorTest {
    private final AppUserRepository users = mock(AppUserRepository.class);
    private final AdminPasswordRecovery recovery = mock(AdminPasswordRecovery.class);
    private static final String[] SAFE = {
        "abigail.admin-password-operator.enabled=true", "spring.main.web-application-type=none",
        "spring.flyway.enabled=false", "spring.jpa.hibernate.ddl-auto=validate", "spring.sql.init.mode=never"
    };

    @Test void requiresAnInteractiveConsoleBeforeAccessingAccounts() {
        var env = new MockEnvironment().withProperty("spring.main.web-application-type", "none")
                .withProperty("spring.flyway.enabled", "false").withProperty("spring.jpa.hibernate.ddl-auto", "validate")
                .withProperty("spring.sql.init.mode", "never");
        assertThatThrownBy(() -> AdminPasswordOperator.operate(env, users, recovery, null))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("terminal interativo");
        verifyNoInteractions(users, recovery);
    }

    @Test void refusesSchemaChangesAndSimultaneousOperatorsBeforeNormalBeans() {
        for (String invalid : new String[] { "spring.flyway.enabled=true", "spring.jpa.hibernate.ddl-auto=update",
                "spring.sql.init.mode=always", "abigail.bootstrap.enabled=true", "abigail.mfa-operator.enabled=true",
                "abigail.restore-session-operator.enabled=true", "abigail.security.session-mode=false" }) {
            var started = new AtomicBoolean();
            new ApplicationContextRunner().withUserConfiguration(AdminPasswordOperator.class)
                    .withBean(AppUserRepository.class, () -> users).withBean(AdminPasswordRecovery.class, () -> recovery)
                    .withBean("probe", Object.class, () -> { started.set(true); return new Object(); })
                    .withPropertyValues(SAFE).withPropertyValues(invalid).run(context -> {
                        assertThat(context).hasFailed();
                        assertThat(started).isFalse();
                    });
        }
    }

    @Test void refusesAWebContextEvenIfPropertyClaimsNonWeb() {
        var started = new AtomicBoolean();
        new WebApplicationContextRunner().withUserConfiguration(AdminPasswordOperator.class)
                .withBean(AppUserRepository.class, () -> users).withBean(AdminPasswordRecovery.class, () -> recovery)
                .withBean("probe", Object.class, () -> { started.set(true); return new Object(); })
                .withPropertyValues(SAFE).run(context -> {
                    assertThat(context).hasFailed();
                    assertThat(started).isFalse();
                });
    }
}
