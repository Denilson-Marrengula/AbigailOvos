package com.abigailovos.security;

import java.io.Console;
import org.springframework.beans.factory.config.BeanFactoryPostProcessor;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;

/** Explicit local recovery operation; callers must stop every server using the database first. */
@Configuration
@ConditionalOnProperty(name = "abigail.restore-session-operator.enabled", havingValue = "true")
class RestoreSessionOperator {
    @Bean
    static BeanFactoryPostProcessor restoreSessionOperatorPreflight(Environment env) {
        return ignored -> OfflineOperatorSafety.check(env);
    }

    @Bean
    @ConditionalOnWebApplication
    static BeanFactoryPostProcessor rejectWebRestoreSessionOperator() {
        return ignored -> { throw new IllegalStateException("Recuperação não é permitida em modo Web."); };
    }

    @Bean
    ApplicationRunner invalidateRestoredSessions(Environment env, RestoreSessionRecovery recovery) {
        return args -> operate(env, recovery, System.console());
    }

    static void operate(Environment env, RestoreSessionRecovery recovery, Console console) {
        OfflineOperatorSafety.check(env);
        if (console == null) throw new IllegalStateException("Operação exige terminal interativo protegido.");
        console.printf("Confirme que esta é a base restaurada aprovada e que todos os servidores estão parados.%n");
        console.printf("As sessões de todas as contas serão invalidadas; nenhum histórico será apagado.%n");
        if (!"CONFIRMAR".equals(console.readLine("Escreva CONFIRMAR para continuar: ")))
            throw new IllegalStateException("Operação não confirmada.");
        int count = recovery.invalidateAll();
        console.printf("Sessões invalidadas para %d contas. Verifique relógios e o procedimento antes de iniciar a API.%n", count);
    }
}
