package com.abigailovos.security;

import org.springframework.core.env.Environment;

/** Shared preflight for privileged local operators, before database beans start. */
final class OfflineOperatorSafety {
    private OfflineOperatorSafety() {}

    static void check(Environment env) {
        int operators = (env.getProperty("abigail.mfa-operator.enabled", Boolean.class, false) ? 1 : 0)
                + (env.getProperty("abigail.admin-password-operator.enabled", Boolean.class, false) ? 1 : 0)
                + (env.getProperty("abigail.restore-session-operator.enabled", Boolean.class, false) ? 1 : 0);
        if (!"none".equalsIgnoreCase(env.getProperty("spring.main.web-application-type", ""))
                || env.getProperty("abigail.bootstrap.enabled", Boolean.class, false)
                || env.getProperty("spring.flyway.enabled", Boolean.class, true)
                || !env.getProperty("abigail.security.session-mode", Boolean.class, true)
                || !"validate".equalsIgnoreCase(env.getProperty("spring.jpa.hibernate.ddl-auto", ""))
                || !"never".equalsIgnoreCase(env.getProperty("spring.sql.init.mode", ""))
                || operators > 1) {
            throw new IllegalStateException("Operação exige modo não Web e sessões, sem inicialização, operadores simultâneos ou alteração de esquema.");
        }
    }
}
