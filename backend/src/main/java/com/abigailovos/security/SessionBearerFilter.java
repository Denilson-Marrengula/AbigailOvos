package com.abigailovos.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Clock;
import java.util.List;
import java.util.Optional;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

/** Experimental session mode only; no Basic authentication is enabled in that mode. */
final class SessionBearerFilter extends OncePerRequestFilter {
    private final RevocableSessions sessions;
    private final Clock clock;

    SessionBearerFilter(RevocableSessions sessions, Clock clock) {
        this.sessions = sessions;
        this.clock = clock;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header == null || !header.trim().regionMatches(true, 0, "Bearer", 0, 6)) {
            chain.doFilter(request, response);
            return;
        }
        String token = bearer(request);
        if (token == null) {
            reject(response, HttpServletResponse.SC_UNAUTHORIZED);
            return;
        }
        Optional<RevocableSessions.Identity> identity;
        try {
            identity = sessions.authenticate(token, clock.instant());
        } catch (RuntimeException error) {
            // Storage failures fail closed; do not log the token or database details.
            reject(response, HttpServletResponse.SC_SERVICE_UNAVAILABLE);
            return;
        }
        if (identity.isEmpty() || !("ADMIN".equals(identity.get().role()) || "SELLER".equals(identity.get().role()))) {
            reject(response, HttpServletResponse.SC_UNAUTHORIZED);
            return;
        }
        var value = identity.get();
        var principal = new SessionPrincipal(value.username(), value.mustChangePassword());
        var authentication = UsernamePasswordAuthenticationToken.authenticated(principal, null,
                List.of(new SimpleGrantedAuthority("ROLE_" + value.role())));
        var context = SecurityContextHolder.createEmptyContext();
        context.setAuthentication(authentication);
        SecurityContextHolder.setContext(context);
        try {
            chain.doFilter(request, response);
        } finally {
            SecurityContextHolder.clearContext();
        }
    }

    static String bearer(HttpServletRequest request) {
        var headers = request.getHeaders("Authorization");
        if (headers == null || !headers.hasMoreElements()) return null;
        String value = headers.nextElement();
        if (headers.hasMoreElements() || value == null) return null;
        value = value.trim();
        if (!value.regionMatches(true, 0, "Bearer ", 0, 7)) return null;
        String token = value.substring(7);
        return token.matches("[A-Za-z0-9_-]{43}") ? token : null;
    }

    private static void reject(HttpServletResponse response, int status) {
        response.setStatus(status);
        response.setHeader("Cache-Control", "no-store");
    }
}
