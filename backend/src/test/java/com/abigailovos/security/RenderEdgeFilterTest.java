package com.abigailovos.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

/** Synthetic servlet requests; no proxy or Render traffic is exercised. */
class RenderEdgeFilterTest {
    @Test void acceptsHttpsForwardedProtocol() throws Exception {
        var request = request("/api/products");
        request.addHeader(RenderEdgeFilter.PROTOCOL_HEADER, "https");
        var response = new MockHttpServletResponse();
        var chain = mock(FilterChain.class);

        new RenderEdgeFilter().doFilter(request, response, chain);

        verify(chain).doFilter(any(), any());
        assertThat(response.getStatus()).isEqualTo(200);
    }

    @Test void acceptsASecureConnectionWithoutTheHeader() throws Exception {
        var request = request("/api/products");
        request.setSecure(true);
        var chain = mock(FilterChain.class);

        new RenderEdgeFilter().doFilter(request, new MockHttpServletResponse(), chain);

        verify(chain).doFilter(any(), any());
    }

    @Test void deniesDirectHttpAndForgedOrAmbiguousHeaders() throws Exception {
        assertDenied(request("/api/products"));

        var http = request("/api/products");
        http.addHeader(RenderEdgeFilter.PROTOCOL_HEADER, "http");
        assertDenied(http);

        var chainOfHeaders = request("/api/products");
        chainOfHeaders.addHeader(RenderEdgeFilter.PROTOCOL_HEADER, "https");
        chainOfHeaders.addHeader(RenderEdgeFilter.PROTOCOL_HEADER, "https");
        assertDenied(chainOfHeaders);

        var commaSeparated = request("/api/products");
        commaSeparated.addHeader(RenderEdgeFilter.PROTOCOL_HEADER, "https, http");
        assertDenied(commaSeparated);

        var empty = request("/api/products");
        empty.addHeader(RenderEdgeFilter.PROTOCOL_HEADER, "   ");
        assertDenied(empty);
    }

    @Test void healthCheckIsNotBlockedByTheEdgeRule() throws Exception {
        var request = request(RenderEdgeFilter.HEALTH_PATH);
        var chain = mock(FilterChain.class);

        new RenderEdgeFilter().doFilter(request, new MockHttpServletResponse(), chain);

        verify(chain).doFilter(any(), any());
    }

    private static void assertDenied(MockHttpServletRequest request) throws Exception {
        var response = new MockHttpServletResponse();
        var chain = mock(FilterChain.class);

        new RenderEdgeFilter().doFilter(request, response, chain);

        assertThat(response.getStatus()).isEqualTo(403);
        assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
        verifyNoInteractions(chain);
    }

    private static MockHttpServletRequest request(String path) {
        return new MockHttpServletRequest("GET", path);
    }
}
