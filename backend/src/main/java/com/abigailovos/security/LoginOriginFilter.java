package com.abigailovos.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

/** Throttle anonymous traffic before parsing credentials or checking CSRF. */
final class LoginOriginFilter extends OncePerRequestFilter {
    static final String CHARGED = LoginOriginFilter.class.getName() + ".charged";
    private final OriginAttemptLimiter origins;
    LoginOriginFilter(OriginAttemptLimiter origins) { this.origins = origins; }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String path = request.getRequestURI().substring(request.getContextPath().length());
        // Platform health checks are anonymous and must not consume user buckets.
        if ("GET".equals(request.getMethod()) && "/api/health".equals(path)) {
            chain.doFilter(request, response);
            return;
        }
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        boolean anonymous = auth == null || !auth.isAuthenticated();
        boolean authenticatedLogin = "POST".equals(request.getMethod()) && "/api/auth/login".equals(path);
        // All anonymous paths are charged, including encoded aliases, malformed
        // requests and CSRF bootstrap; only established sessions are exempt.
        if (!(anonymous || authenticatedLogin)) {
            chain.doFilter(request, response);
            return;
        }
        try {
            if (!origins.charge(request.getRemoteAddr())) {
                response.setStatus(429);
                response.setHeader("Retry-After", "300");
                response.setHeader("Cache-Control", "no-store");
                return;
            }
            request.setAttribute(CHARGED, Boolean.TRUE);
        } catch (RuntimeException error) {
            response.setStatus(HttpServletResponse.SC_SERVICE_UNAVAILABLE);
            response.setHeader("Cache-Control", "no-store");
            return;
        }
        chain.doFilter(request, response);
    }
}
