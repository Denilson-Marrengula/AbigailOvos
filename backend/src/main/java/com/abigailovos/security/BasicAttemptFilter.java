package com.abigailovos.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.web.filter.OncePerRequestFilter;

final class BasicAttemptFilter extends OncePerRequestFilter {
    private final BasicAttemptLimiter limiter = new BasicAttemptLimiter();

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String authorization = request.getHeader("Authorization");
        // Match Spring Security's BasicAuthenticationConverter, including its
        // trimming and permissive scheme prefix, so variants cannot bypass this filter.
        if (authorization == null || !authorization.trim().regionMatches(true, 0, "Basic", 0, 5)) {
            chain.doFilter(request, response);
            return;
        }
        String address = request.getRemoteAddr();
        long retryAfter = limiter.begin(address);
        if (retryAfter > 0) {
            response.setStatus(429);
            response.setHeader("Retry-After", Long.toString(retryAfter));
            response.setHeader("Cache-Control", "no-store");
            return;
        }
        try {
            chain.doFilter(request, response);
        } finally {
            limiter.finish(address, response.getStatus() == HttpServletResponse.SC_UNAUTHORIZED);
        }
    }
}
