package com.abigailovos.security;

import jakarta.servlet.FilterChain;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

/** Raw servlet requests only; these tests do not validate a real proxy chain. */
class LoginOriginFilterTest {
    @AfterEach void clearContext() {
        SecurityContextHolder.clearContext();
    }

    @Test void untrustedForwardingHeadersDoNotChangeTheChargedSocketAddress() throws Exception {
        var limiter = mock(OriginAttemptLimiter.class);
        when(limiter.charge("192.0.2.10")).thenReturn(true);
        var filter = new LoginOriginFilter(limiter);
        var request = request("GET", "/api/csrf", "192.0.2.10");
        request.addHeader("X-Forwarded-For", "203.0.113.1, 203.0.113.2");
        request.addHeader("X-Forwarded-For", "203.0.113.3");
        request.addHeader("X-Real-IP", "203.0.113.4");
        request.addHeader("True-Client-IP", "203.0.113.5");
        request.addHeader("CF-Connecting-IP", "203.0.113.6");
        request.addHeader("Forwarded", "for=203.0.113.7;proto=https");
        var response = new MockHttpServletResponse();
        var chain = mock(FilterChain.class);

        filter.doFilter(request, response, chain);

        verify(limiter).charge("192.0.2.10");
        verifyNoMoreInteractions(limiter);
        verify(chain).doFilter(request, response);
    }

    @Test void clientsBehindOneProxyShareItsBucketWithoutAValidatedResolver() throws Exception {
        var limiter = mock(OriginAttemptLimiter.class);
        when(limiter.charge("192.0.2.10")).thenReturn(true, false);
        var filter = new LoginOriginFilter(limiter);
        var first = request("GET", "/api/csrf", "192.0.2.10");
        first.addHeader("X-Forwarded-For", "203.0.113.1");
        var second = request("GET", "/api/csrf", "192.0.2.10");
        second.addHeader("X-Forwarded-For", "203.0.113.2");
        var firstResponse = new MockHttpServletResponse();
        var secondResponse = new MockHttpServletResponse();
        var chain = mock(FilterChain.class);

        filter.doFilter(first, firstResponse, chain);
        filter.doFilter(second, secondResponse, chain);

        verify(limiter, times(2)).charge("192.0.2.10");
        verifyNoMoreInteractions(limiter);
        verify(chain).doFilter(first, firstResponse);
        verify(chain, never()).doFilter(second, secondResponse);
        assertThat(secondResponse.getStatus()).isEqualTo(429);
        assertThat(secondResponse.getHeader("Retry-After")).isEqualTo("300");
        assertThat(secondResponse.getHeader("Cache-Control")).isEqualTo("no-store");
    }

    @Test void unavailableLimiterFailsClosedWithoutReturningItsError() throws Exception {
        var limiter = mock(OriginAttemptLimiter.class);
        when(limiter.charge("192.0.2.10")).thenThrow(new IllegalStateException("secret-fake-error"));
        var filter = new LoginOriginFilter(limiter);
        var request = request("GET", "/api/csrf", "192.0.2.10");
        var response = new MockHttpServletResponse();
        var chain = mock(FilterChain.class);

        filter.doFilter(request, response, chain);

        assertThat(response.getStatus()).isEqualTo(503);
        assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(response.getContentAsString()).doesNotContain("secret-fake-error");
        verifyNoInteractions(chain);
    }

    @Test void healthCheckDoesNotConsumeTheOriginBucket() throws Exception {
        var limiter = mock(OriginAttemptLimiter.class);
        var filter = new LoginOriginFilter(limiter);
        var request = request("GET", "/api/health", "192.0.2.10");
        var response = new MockHttpServletResponse();
        var chain = mock(FilterChain.class);

        filter.doFilter(request, response, chain);

        verifyNoInteractions(limiter);
        verify(chain).doFilter(request, response);
    }

    @Test void authenticatedSessionsAreExemptExceptWhenPostingLogin() throws Exception {
        var limiter = mock(OriginAttemptLimiter.class);
        when(limiter.charge("192.0.2.10")).thenReturn(true);
        var filter = new LoginOriginFilter(limiter);
        SecurityContextHolder.getContext().setAuthentication(
                UsernamePasswordAuthenticationToken.authenticated(
                        "seller", null, List.of(new SimpleGrantedAuthority("ROLE_SELLER"))));
        var get = request("GET", "/api/products", "192.0.2.10");
        var login = request("POST", "/api/auth/login", "192.0.2.10");
        var chain = mock(FilterChain.class);

        filter.doFilter(get, new MockHttpServletResponse(), chain);
        filter.doFilter(login, new MockHttpServletResponse(), chain);

        verify(limiter).charge("192.0.2.10");
        verifyNoMoreInteractions(limiter);
        verify(chain, times(2)).doFilter(any(), any());
    }

    private static MockHttpServletRequest request(String method, String path, String remote) {
        var request = new MockHttpServletRequest(method, path);
        request.setRemoteAddr(remote);
        return request;
    }
}
