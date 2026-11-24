package com.abigailovos.security;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.www.BasicAuthenticationFilter;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.csrf.CsrfFilter;
import org.springframework.http.HttpStatus;
import jakarta.servlet.DispatcherType;
import java.time.Clock;
import static org.springframework.http.HttpMethod.GET;
import static org.springframework.http.HttpMethod.POST;
import static org.springframework.http.HttpMethod.PATCH;
import static org.springframework.http.HttpMethod.PUT;
import static org.springframework.http.HttpMethod.DELETE;

@Configuration
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
public class SecurityConfiguration {
    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http,
            @Value("${abigail.security.require-https:false}") boolean requireHttps,
            @Value("${abigail.security.session-mode:true}") boolean sessionMode,
            RevocableSessions sessions, OriginAttemptLimiter origins, Clock clock) throws Exception {
        if (requireHttps) {
            http.requiresChannel(channel -> channel.anyRequest().requiresSecure());
        }
        http.sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS));
        if (sessionMode) {
            // Session mode does not accept Basic as an alternative authentication path.
            http.httpBasic(AbstractHttpConfigurer::disable).formLogin(AbstractHttpConfigurer::disable)
                    .logout(AbstractHttpConfigurer::disable)
                    .exceptionHandling(errors -> errors.authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)))
                    .addFilterBefore(new LoginOriginFilter(origins), CsrfFilter.class)
                    .addFilterBefore(new SessionBearerFilter(sessions, clock), LoginOriginFilter.class)
                    .addFilterAfter(new PasswordChangeRequiredFilter(), SessionBearerFilter.class);
        } else {
            // Legacy test-only mode; still unsafe for real administrative data.
            http.addFilterBefore(new BasicAttemptFilter(), BasicAuthenticationFilter.class)
                    .addFilterAfter(new PasswordChangeRequiredFilter(), BasicAuthenticationFilter.class)
                    .httpBasic(basic -> {});
        }
        return http.authorizeHttpRequests(auth -> {
                auth.requestMatchers(GET, "/api/health").permitAll();
                auth.dispatcherTypeMatchers(DispatcherType.ERROR).permitAll();
                if (sessionMode) {
                    auth.requestMatchers(GET, "/api/csrf").permitAll()
                            .requestMatchers(POST, "/api/auth/login").permitAll()
                            .requestMatchers(POST, "/api/auth/logout").hasAnyRole("ADMIN", "SELLER");
                } else {
                    auth.requestMatchers(GET, "/api/csrf").hasAnyRole("ADMIN", "SELLER");
                }
                auth.requestMatchers(GET, "/api/me").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(PUT, "/api/account/password").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(GET, "/api/reports/sales", "/api/reports/activity").hasRole("ADMIN")
                .requestMatchers(GET, "/api/audit/events").hasRole("ADMIN")
                .requestMatchers(GET, "/api/sales", "/api/sales/capabilities", "/api/sales/search").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(POST, "/api/sales").hasRole("SELLER")
                .requestMatchers(PATCH, "/api/sales/*/deliver", "/api/sales/*/pay").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(PATCH, "/api/sales/*/cancel").hasRole("SELLER")
                .requestMatchers(GET, "/api/users").hasRole("ADMIN")
                .requestMatchers(POST, "/api/users").hasRole("ADMIN")
                .requestMatchers(DELETE, "/api/users/*").hasRole("ADMIN")
                .requestMatchers(PATCH, "/api/users/*/status").hasRole("ADMIN")
                .requestMatchers(PATCH, "/api/users/*/password-reset").hasRole("ADMIN")
                .requestMatchers(PUT, "/api/users/*/profile").hasRole("ADMIN")
                .requestMatchers(GET, "/api/products", "/api/products/*").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(POST, "/api/products").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(PUT, "/api/products/*").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(PUT, "/api/products/*/minimum-stock").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(DELETE, "/api/products/*/minimum-stock").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(PATCH, "/api/products/*/status").hasRole("ADMIN")
                .requestMatchers(GET, "/api/customers", "/api/customers/*").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(PUT, "/api/customers/*").hasRole("SELLER")
                .requestMatchers(GET, "/api/stock/*/movements").hasRole("ADMIN")
                .requestMatchers(GET, "/api/stock/*").hasAnyRole("ADMIN", "SELLER")
                .requestMatchers(POST, "/api/stock/movements").hasRole("SELLER")
                .anyRequest().denyAll();
                })
                .build();
    }
}
