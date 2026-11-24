package com.abigailovos.security;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Available only when the experimental session-only security chain is selected. */
@RestController
@RequestMapping("/api/auth")
@ConditionalOnProperty(name = "abigail.security.session-mode", havingValue = "true", matchIfMissing = true)
class SessionLoginController {
    private final SessionLogin login;
    private final RevocableSessions sessions;
    private final OriginAttemptLimiter origins;
    private final Clock clock;

    SessionLoginController(SessionLogin login, RevocableSessions sessions, OriginAttemptLimiter origins, Clock clock) {
        this.login = login;
        this.sessions = sessions;
        this.origins = origins;
        this.clock = clock;
    }

    // Older clients may still send a code; it is ignored and never used for login.
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Credentials(@NotNull @Size(max = 100) String username,
            @NotNull @Size(max = 72) String password) {
        @Override public String toString() { return "Credentials[redacted]"; }
    }
    record LoginResponse(String token, Instant expiresAt, String username, List<String> roles, boolean mustChangePassword) {
        @Override public String toString() { return "LoginResponse[redacted]"; }
    }

    @PostMapping("/login")
    ResponseEntity<LoginResponse> login(@Valid @RequestBody Credentials credentials, HttpServletRequest request) {
        // Defense for an already authenticated client using a route alias that
        // did not match the filter's literal login path. Never trust forwarding headers.
        if (!Boolean.TRUE.equals(request.getAttribute(LoginOriginFilter.CHARGED))) {
            try {
                if (!origins.charge(request.getRemoteAddr()))
                    return ResponseEntity.status(429).header("Retry-After", "300").cacheControl(CacheControl.noStore()).build();
            } catch (RuntimeException error) {
                return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).cacheControl(CacheControl.noStore()).build();
            }
        }
        // A rejected outcome must return normally so the failure counter commits.
        SessionLogin.Outcome outcome = login.authenticate(credentials.username(), credentials.password());
        if (!outcome.accepted()) return ResponseEntity.status(HttpStatus.UNAUTHORIZED).cacheControl(CacheControl.noStore()).build();
        var issued = outcome.issued();
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(new LoginResponse(issued.token(), issued.expiresAt(), outcome.username(),
                        List.of("ROLE_" + outcome.role()), outcome.mustChangePassword()));
    }

    @PostMapping("/logout")
    ResponseEntity<Void> logout(HttpServletRequest request) {
        String token = SessionBearerFilter.bearer(request);
        if (token == null) return ResponseEntity.status(HttpStatus.UNAUTHORIZED).cacheControl(CacheControl.noStore()).build();
        sessions.revoke(token, clock.instant());
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }
}
