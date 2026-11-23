package com.abigailovos.security;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;
import jakarta.servlet.DispatcherType;
import static org.springframework.http.HttpMethod.GET;
import static org.springframework.http.HttpMethod.POST;
import static org.springframework.http.HttpMethod.PATCH;
import static org.springframework.http.HttpMethod.PUT;

@Configuration
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
public class SecurityConfiguration {
    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http,
            @Value("${abigail.security.require-https:false}") boolean requireHttps) throws Exception {
        if (requireHttps) {
            http.requiresChannel(channel -> channel.anyRequest().requiresSecure());
        }
        return http.authorizeHttpRequests(auth -> auth
                .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
                .requestMatchers(GET, "/api/me").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(GET, "/api/csrf").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(GET, "/api/reports/sales").hasRole("ADMIN")
                .requestMatchers(GET, "/api/sales").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(POST, "/api/sales").hasRole("SELLER")
                .requestMatchers(PATCH, "/api/sales/*/deliver", "/api/sales/*/cancel", "/api/sales/*/pay").hasRole("SELLER")
                .requestMatchers(GET, "/api/users").hasRole("ADMIN")
                .requestMatchers(POST, "/api/users").hasRole("ADMIN")
                .requestMatchers(PATCH, "/api/users/*/status").hasRole("ADMIN")
                .requestMatchers(PUT, "/api/users/*/profile").hasRole("ADMIN")
                .requestMatchers(GET, "/api/products", "/api/products/*").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(POST, "/api/products").hasRole("ADMIN")
                .requestMatchers(PUT, "/api/products/*").hasRole("ADMIN")
                .requestMatchers(PATCH, "/api/products/*/status").hasRole("ADMIN")
                .requestMatchers(GET, "/api/customers", "/api/customers/*").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(GET, "/api/stock/*/movements").hasRole("ADMIN")
                .requestMatchers(GET, "/api/stock/*").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(POST, "/api/stock/movements").hasRole("SELLER")
                .anyRequest().denyAll())
                .httpBasic(basic -> {
                })
                .build();
    }
}
