package com.abigailovos.security;

import java.util.regex.Pattern;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;

/** Explicit one-time local provisioning; do not enable on multiple instances. */
@Configuration
@ConditionalOnProperty(name = "abigail.bootstrap.enabled", havingValue = "true")
class InitialAdmin {
    @Bean
    ApplicationRunner provisionFirstAdmin(AdminProvisioner provisioner, Environment environment) {
        return args -> {
            if (!"none".equalsIgnoreCase(environment.getProperty("spring.main.web-application-type", ""))) {
                throw new IllegalStateException("Inicialização inicial exige modo não Web");
            }
            provisioner.provision(environment.getProperty("abigail.bootstrap.username"),
                    environment.getProperty("abigail.bootstrap.password"),
                    environment.getProperty("abigail.bootstrap.seller-username"),
                    environment.getProperty("abigail.bootstrap.seller-password"));
        };
    }

    @Bean
    AdminProvisioner adminProvisioner(AppUserRepository users, PasswordEncoder encoder) {
        return new AdminProvisioner(users, encoder);
    }

    static class AdminProvisioner {
        private static final Pattern USERNAME = Pattern.compile("[a-zA-Z0-9._-]{3,100}");
        private static final Pattern PASSWORD = Pattern.compile("[\\x20-\\x7E]{12,72}");
        private final AppUserRepository users;
        private final PasswordEncoder encoder;

        AdminProvisioner(AppUserRepository users, PasswordEncoder encoder) {
            this.users = users;
            this.encoder = encoder;
        }

        @Transactional
        public void provision(String username, String password, String sellerUsername, String sellerPassword) {
            if (!valid(username, password)) {
                throw new IllegalStateException("Credenciais iniciais inválidas");
            }
            if ((sellerUsername != null || sellerPassword != null)
                    && (!valid(sellerUsername, sellerPassword) || username.equalsIgnoreCase(sellerUsername))) {
                throw new IllegalStateException("Credenciais iniciais do vendedor inválidas");
            }
            if (users.count() != 0) {
                throw new IllegalStateException("Inicialização recusada: já existem contas");
            }
            users.saveAndFlush(new AppUser(username, encoder.encode(password), "ADMIN"));
            if (sellerUsername != null) {
                users.saveAndFlush(new AppUser(sellerUsername, encoder.encode(sellerPassword), "SELLER"));
            }
        }

        private boolean valid(String username, String password) {
            return username != null && USERNAME.matcher(username).matches()
                    && password != null && !password.isBlank() && PASSWORD.matcher(password).matches();
        }
    }
}
