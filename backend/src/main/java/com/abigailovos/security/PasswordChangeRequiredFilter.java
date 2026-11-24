package com.abigailovos.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

/** A temporary credential can only discover its state and change the password. */
final class PasswordChangeRequiredFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        Object principal = authentication == null ? null : authentication.getPrincipal();
        boolean mustChange = (principal instanceof AccountPrincipal account && account.mustChangePassword())
                || (principal instanceof SessionPrincipal session && session.mustChangePassword());
        if (mustChange) {
            String path = request.getRequestURI().substring(request.getContextPath().length());
            boolean allowed = ("GET".equals(request.getMethod()) && ("/api/me".equals(path) || "/api/csrf".equals(path)))
                    || ("PUT".equals(request.getMethod()) && "/api/account/password".equals(path))
                    || ("POST".equals(request.getMethod()) && "/api/auth/logout".equals(path));
            if (!allowed) {
                response.setStatus(HttpServletResponse.SC_FORBIDDEN);
                response.setHeader("Cache-Control", "no-store");
                return;
            }
        }
        chain.doFilter(request, response);
    }
}
