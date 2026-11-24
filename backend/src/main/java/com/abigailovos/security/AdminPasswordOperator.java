package com.abigailovos.security;

import java.io.Console;
import java.util.Arrays;
import org.springframework.beans.factory.config.BeanFactoryPostProcessor;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;

/** Local privileged password recovery; identity verification must occur out of band. */
@Configuration
@ConditionalOnProperty(name = "abigail.admin-password-operator.enabled", havingValue = "true")
class AdminPasswordOperator {
    @Bean
    static BeanFactoryPostProcessor adminPasswordOperatorPreflight(Environment env) {
        return ignored -> OfflineOperatorSafety.check(env);
    }

    @Bean
    @ConditionalOnWebApplication
    static BeanFactoryPostProcessor rejectWebAdminPasswordOperator() {
        return ignored -> { throw new IllegalStateException("Recuperação não é permitida em modo Web."); };
    }

    @Bean
    ApplicationRunner resetAdminPassword(Environment env, AppUserRepository users, AdminPasswordRecovery recovery) {
        return args -> operate(env, users, recovery, System.console());
    }

    static void operate(Environment env, AppUserRepository users, AdminPasswordRecovery recovery, Console console) {
        OfflineOperatorSafety.check(env);
        if (console == null) throw new IllegalStateException("Operação exige terminal interativo protegido.");
        String username = env.getProperty("abigail.admin-password-operator.username", "");
        if (!username.matches("[a-zA-Z0-9._-]{3,100}")) throw new IllegalStateException("Operação administrativa inválida.");
        AppUser account = users.findByUsername(username)
                .filter(user -> user.isEnabled() && "ADMIN".equals(user.getRole()))
                .orElseThrow(() -> new IllegalStateException("Conta administrativa indisponível."));
        console.printf("Verifique a identidade por um meio independente e proteja este terminal.%n");
        console.printf("A redefinição invalida sessões e exige alteração da palavra-passe em 24 horas.%n");
        if (!"CONFIRMAR".equals(console.readLine("Escreva CONFIRMAR para continuar: ")))
            throw new IllegalStateException("Operação não confirmada.");
        char[] first = null;
        char[] second = null;
        try {
            first = console.readPassword("Nova palavra-passe temporária (12 a 72 caracteres ASCII): ");
            second = console.readPassword("Confirme a palavra-passe temporária: ");
            if (first == null || second == null || !Arrays.equals(first, second))
                throw new IllegalStateException("Confirmação indisponível ou diferente.");
            recovery.reset(account.getId(), first);
            console.printf("Redefinição registada. A palavra-passe temporária deve ser alterada no novo acesso.%n");
        } finally {
            if (first != null) Arrays.fill(first, '\0');
            if (second != null) Arrays.fill(second, '\0');
        }
    }
}
