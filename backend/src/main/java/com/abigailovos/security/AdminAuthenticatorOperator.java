package com.abigailovos.security;

import java.io.Console;
import java.time.Instant;
import java.util.Arrays;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.beans.factory.config.BeanFactoryPostProcessor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;

/**
 * Historical enrollment code is retained to preserve the implementation, but
 * activation is refused: the application no longer uses a second factor.
 */
@Configuration
@ConditionalOnProperty(name = "abigail.mfa-operator.enabled", havingValue = "true")
class AdminAuthenticatorOperator {
    /** Refuse unsafe configuration before Flyway, SQL initialization or Hibernate can start. */
    @Bean
    static BeanFactoryPostProcessor authenticatorOperatorPreflight(Environment env) {
        return ignored -> {
            throw new IllegalStateException("A inscrição de autenticador foi desativada; o acesso usa palavra-passe.");
        };
    }

    /** Fail even if a programmatic web context contradicts the environment property. */
    @Bean
    @ConditionalOnWebApplication
    static BeanFactoryPostProcessor rejectWebAuthenticatorOperator() {
        return ignored -> { throw new IllegalStateException("Operação de autenticador não é permitida em modo Web."); };
    }

    @Bean
    ApplicationRunner enrollAdminAuthenticator(Environment env, AppUserRepository users, AdminAuthenticator mfa) {
        return args -> operate(env, users, mfa, System.console());
    }

    static void operate(Environment env, AppUserRepository users, AdminAuthenticator mfa, Console console) {
        OfflineOperatorSafety.check(env);
        if (console == null) throw new IllegalStateException("Operação exige terminal interativo protegido.");
        String username = env.getProperty("abigail.mfa-operator.username", "");
        String mode = env.getProperty("abigail.mfa-operator.mode", "");
        if (!username.matches("[a-zA-Z0-9._-]{3,100}")
                || (!"initial".equals(mode) && !"replace".equals(mode))) {
            throw new IllegalStateException("Operação administrativa inválida.");
        }
        AppUser account = users.findByUsername(username)
                .filter(user -> user.isEnabled() && "ADMIN".equals(user.getRole()))
                .orElseThrow(() -> new IllegalStateException("Conta administrativa indisponível."));
        console.printf("Verifique a identidade por um meio independente e proteja este terminal.%n");
        console.printf("A operação '%s' revogará as sessões existentes após a confirmação.%n", mode);
        String approval = console.readLine("Escreva CONFIRMAR para continuar: ");
        if (!"CONFIRMAR".equals(approval)) throw new IllegalStateException("Operação não confirmada.");
        AdminAuthenticator.Enrollment enrollment = mfa.stage(account.getId(), "replace".equals(mode), Instant.now());
        console.printf("Insira manualmente este segredo na aplicação autenticadora: %s%n", enrollment.secret());
        console.printf("Código de 6 dígitos, SHA-1, período de 30 segundos. Não partilhe nem fotografe o segredo.%n");
        char[] input = console.readPassword("Código atual: ");
        if (input == null) throw new IllegalStateException("Confirmação indisponível.");
        boolean confirmed;
        try {
            confirmed = mfa.confirm(account.getId(), enrollment.id(), new String(input), Instant.now());
        } finally {
            Arrays.fill(input, '\0');
        }
        if (!confirmed) throw new IllegalStateException("Código inválido ou inscrição expirada.");
        console.printf("Autenticador registado. O código usado não pode ser reutilizado.%n");
    }
}
