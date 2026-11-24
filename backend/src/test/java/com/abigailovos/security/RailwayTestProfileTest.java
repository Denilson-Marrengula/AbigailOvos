package com.abigailovos.security;

import org.springframework.boot.web.server.Cookie;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.web.servlet.server.Session;
import org.springframework.boot.autoconfigure.web.ServerProperties;
import org.springframework.test.context.ActiveProfiles;
import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("railway-test")
class RailwayTestProfileTest {
    @Autowired ServerProperties server;

    @Test void testProfileKeepsSessionCookiesSecureBehindRailwayTls() {
        Session.Cookie cookie = server.getServlet().getSession().getCookie();
        assertThat(cookie.getSecure()).isTrue();
        assertThat(cookie.getHttpOnly()).isTrue();
        assertThat(cookie.getSameSite()).isEqualTo(Cookie.SameSite.STRICT);
        assertThat(server.getForwardHeadersStrategy()).isEqualTo(ServerProperties.ForwardHeadersStrategy.NONE);
    }
}
