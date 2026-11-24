package com.abigailovos.security;

import java.util.Arrays;
import java.util.Base64;
import org.springframework.beans.factory.config.BeanFactoryPostProcessor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;

/** Fails before normal beans start if the direct-TLS production profile would use Basic or missing keys. */
@Configuration
@Profile("production")
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
class ProductionSecurityGuard {
    @Bean
    static BeanFactoryPostProcessor productionSecurityPreflight(Environment env) {
        return ignored -> {
            if (!env.getProperty("abigail.security.session-mode", Boolean.class, false)
                    || !env.getProperty("abigail.security.require-https", Boolean.class, false)) {
                throw new IllegalStateException("O perfil de produção exige sessões e HTTPS.");
            }
            byte[] origin = null;
            try {
                origin = key(env.getProperty("ABIGAIL_AUTH_ORIGIN_KEY", ""));
            } finally {
                if (origin != null) Arrays.fill(origin, (byte) 0);
            }
        };
    }

    private static byte[] key(String configured) {
        byte[] decoded = null;
        try {
            decoded = Base64.getDecoder().decode(configured);
            if (decoded.length == 32 && Base64.getEncoder().encodeToString(decoded).equals(configured)) return decoded;
        } catch (IllegalArgumentException ignored) {
            // Never include key material in an exception.
        }
        if (decoded != null) Arrays.fill(decoded, (byte) 0);
        throw new IllegalStateException("Chaves de segurança ausentes ou inválidas.");
    }
}
