package com.abigailovos.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Collections;
import java.util.List;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Denies requests that did not arrive through the Render HTTPS edge. The
 * forwarded protocol is used only as a denial signal, never to grant access.
 */
final class RenderEdgeFilter extends OncePerRequestFilter {
    static final String PROTOCOL_HEADER = "X-Forwarded-Proto";
    static final String HEALTH_PATH = "/api/health";

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String path = request.getRequestURI().substring(request.getContextPath().length());
        // Render's health check must not be blocked by edge or rate-limit rules.
        if ("GET".equals(request.getMethod()) && HEALTH_PATH.equals(path)) {
            chain.doFilter(request, response);
            return;
        }
        if (request.isSecure()) {
            chain.doFilter(request, response);
            return;
        }
        if (hasSingleHttpsHeader(request)) {
            chain.doFilter(request, response);
            return;
        }
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        response.setHeader("Cache-Control", "no-store");
    }

    /** A single, exact header is required; repeated or comma-separated values are ambiguous. */
    private static boolean hasSingleHttpsHeader(HttpServletRequest request) {
        List<String> values = Collections.list(request.getHeaders(PROTOCOL_HEADER));
        return values.size() == 1 && "https".equalsIgnoreCase(values.get(0).trim());
    }
}
