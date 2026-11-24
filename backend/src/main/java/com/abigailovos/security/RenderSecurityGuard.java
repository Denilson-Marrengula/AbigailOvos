package com.abigailovos.security;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.Arrays;
import java.util.Base64;
import java.util.Locale;
import java.util.regex.Pattern;
import org.springframework.beans.factory.config.BeanFactoryPostProcessor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;

/** Fail-closed preflight for the Render edge profile. Messages never contain secrets. */
@Configuration(proxyBeanMethods = false)
@Profile("render")
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
class RenderSecurityGuard {
    private static final Pattern HOST = Pattern.compile(
            "(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
                    + "(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+");

    private RenderSecurityGuard() { }

    @Bean
    static BeanFactoryPostProcessor renderSecurityPreflight(Environment env) {
        return ignored -> {
            if (!env.getProperty("abigail.security.session-mode", Boolean.class, false)
                    || env.getProperty("abigail.security.require-https", Boolean.class, true)
                    || !env.getProperty("abigail.render.edge-confirmed", Boolean.class, false)) {
                throw new IllegalStateException("O perfil Render exige sessões, HTTPS na entrada e confirmação do proxy.");
            }
            if (!validOrigin(env.getProperty("abigail.render.public-origin", ""))
                    || !validDatabaseUrl(env.getProperty("DB_URL", ""))
                    || env.getProperty("DB_MIGRATIONS_ENABLED", Boolean.class, false)
                    || Boolean.parseBoolean(env.getProperty("ABIGAIL_BOOTSTRAP_ENABLED", "false"))) {
                throw new IllegalStateException("Configuração Render inválida ou incompleta.");
            }
            byte[] origin = null;
            try {
                origin = key(env.getProperty("ABIGAIL_AUTH_ORIGIN_KEY", ""));
            } finally {
                if (origin != null) Arrays.fill(origin, (byte) 0);
            }
        };
    }

    static boolean validOrigin(String value) {
        if (value == null || value.isBlank()) return false;
        try {
            URI uri = new URI(value.trim());
            String host = uri.getHost();
            if (!"https".equals(uri.getScheme()) || host == null || uri.getUserInfo() != null
                    || uri.getRawQuery() != null || uri.getRawFragment() != null) return false;
            String path = uri.getRawPath();
            if (path != null && !path.isEmpty() && !"/".equals(path)) return false;
            int port = uri.getPort();
            return (port == -1 || port == 443)
                    && HOST.matcher(host.toLowerCase(Locale.ROOT)).matches();
        } catch (URISyntaxException ignored) {
            return false;
        }
    }

    static boolean validDatabaseUrl(String value) {
        if (value == null || !value.startsWith("jdbc:mysql://")) return false;
        String rest = value.substring("jdbc:mysql://".length());
        int slash = rest.indexOf('/');
        if (slash < 0 || rest.substring(0, slash).contains("@")) return false;
        String lower = value.toLowerCase(Locale.ROOT);
        return lower.contains("sslmode=verify_identity")
                && !lower.contains("allowpublickeyretrieval=true")
                && !lower.contains("user=") && !lower.contains("password=");
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
        throw new IllegalStateException("Chave de limite por origem ausente ou inválida.");
    }
}
