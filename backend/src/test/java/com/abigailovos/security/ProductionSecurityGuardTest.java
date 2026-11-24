package com.abigailovos.security;

import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.WebApplicationContextRunner;
import static org.assertj.core.api.Assertions.*;

/** Only structural checks; synthetic keys are not suitable for use outside tests. */
class ProductionSecurityGuardTest {
    private static final String KEY_B = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=";
    private static final String[] SAFE = {
        "abigail.security.session-mode=true", "abigail.security.require-https=true",
        "ABIGAIL_AUTH_ORIGIN_KEY=" + KEY_B
    };

    @Test void failsBeforeNormalBeansIfBasicTlsOrKeysAreUnsafe() {
        for (String invalid : new String[] { "abigail.security.session-mode=false", "abigail.security.require-https=false",
                "ABIGAIL_AUTH_ORIGIN_KEY=", "ABIGAIL_AUTH_ORIGIN_KEY=not-a-key" }) {
            var started = new AtomicBoolean();
            runner(started).withPropertyValues(SAFE).withPropertyValues(invalid).run(context -> {
                assertThat(context).hasFailed();
                assertThat(started).isFalse();
            });
        }
    }

    @Test void acceptsValidOriginKeyWithoutAnAuthenticatorKey() {
        var started = new AtomicBoolean();
        runner(started).withPropertyValues(SAFE).run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(started).isTrue();
        });
    }

    private WebApplicationContextRunner runner(AtomicBoolean started) {
        return new WebApplicationContextRunner().withUserConfiguration(ProductionSecurityGuard.class)
                .withInitializer(context -> context.getEnvironment().setActiveProfiles("production"))
                .withBean("probe", Object.class, () -> { started.set(true); return new Object(); });
    }
}
