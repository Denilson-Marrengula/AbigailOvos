package com.abigailovos.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.Base64;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

/** Synthetic configuration only: no connection, secret or deployment is involved. */
class RenderSecurityGuardTest {
    private static final String ORIGIN_KEY = Base64.getEncoder().encodeToString(new byte[32]);
    private static final String URL = "jdbc:mysql://gateway.example.tidbcloud.com:4000/"
            + "abigailovos_tidb_test_0f90d84d9d5245e1?sslMode=VERIFY_IDENTITY";

    private static MockEnvironment complete() {
        var env = new MockEnvironment();
        env.setProperty("abigail.security.session-mode", "true");
        env.setProperty("abigail.security.require-https", "false");
        env.setProperty("abigail.render.edge-confirmed", "true");
        env.setProperty("abigail.render.public-origin", "https://abigailovos.onrender.com");
        env.setProperty("DB_URL", URL);
        env.setProperty("DB_MIGRATIONS_ENABLED", "false");
        env.setProperty("ABIGAIL_BOOTSTRAP_ENABLED", "false");
        env.setProperty("ABIGAIL_AUTH_ORIGIN_KEY", ORIGIN_KEY);
        return env;
    }

    private static void preflight(MockEnvironment env) {
        RenderSecurityGuard.renderSecurityPreflight(env).postProcessBeanFactory(null);
    }

    @Test void acceptsCompleteSyntheticConfiguration() {
        preflight(complete());
    }

    @Test void refusesToStartWhenAnAssumptionIsMissing() {
        assertRefused("abigail.render.edge-confirmed", "false");
        assertRefused("abigail.security.require-https", "true");
        assertRefused("DB_MIGRATIONS_ENABLED", "true");
        assertRefused("ABIGAIL_BOOTSTRAP_ENABLED", "true");
        assertRefused("ABIGAIL_AUTH_ORIGIN_KEY", "not-a-key");
        assertThatThrownBy(() -> preflight(new MockEnvironment())).isInstanceOf(IllegalStateException.class);
    }

    private static void assertRefused(String key, String value) {
        var env = complete();
        env.setProperty(key, value);
        assertThatThrownBy(() -> preflight(env)).isInstanceOf(IllegalStateException.class);
    }

    @Test void validatesThePublicOrigin() {
        assertThat(RenderSecurityGuard.validOrigin("https://abigailovos.onrender.com")).isTrue();
        assertThat(RenderSecurityGuard.validOrigin("https://exemplo.example:443/")).isTrue();
        assertThat(RenderSecurityGuard.validOrigin("http://abigailovos.onrender.com")).isFalse();
        assertThat(RenderSecurityGuard.validOrigin("https://user@abigailovos.onrender.com")).isFalse();
        assertThat(RenderSecurityGuard.validOrigin("https://abigailovos.onrender.com/caminho")).isFalse();
        assertThat(RenderSecurityGuard.validOrigin("https://abigailovos.onrender.com?x=1")).isFalse();
        assertThat(RenderSecurityGuard.validOrigin("https://localhost")).isFalse();
        assertThat(RenderSecurityGuard.validOrigin("https://*.example.com")).isFalse();
    }

    @Test void requiresIdentityVerifiedDatabaseTlsWithoutEmbeddedCredentials() {
        assertThat(RenderSecurityGuard.validDatabaseUrl(URL)).isTrue();
        assertThat(RenderSecurityGuard.validDatabaseUrl("jdbc:mysql://host:4000/base?sslMode=VERIFY_IDENTITY")).isTrue();
        assertThat(RenderSecurityGuard.validDatabaseUrl("jdbc:mysql://host:4000/base?sslMode=DISABLED")).isFalse();
        assertThat(RenderSecurityGuard.validDatabaseUrl("jdbc:mysql://user:pw@host:4000/base?sslMode=VERIFY_IDENTITY")).isFalse();
        assertThat(RenderSecurityGuard.validDatabaseUrl("jdbc:mysql://host:4000/base?sslMode=VERIFY_IDENTITY&allowPublicKeyRetrieval=true")).isFalse();
        assertThat(RenderSecurityGuard.validDatabaseUrl("jdbc:mysql://host:4000/base?user=x&sslMode=VERIFY_IDENTITY")).isFalse();
    }
}
