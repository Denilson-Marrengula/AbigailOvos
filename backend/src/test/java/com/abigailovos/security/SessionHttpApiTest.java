package com.abigailovos.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Experimental session mode only; no real network or database. */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:session_http;MODE=MySQL;DB_CLOSE_DELAY=-1",
        "abigail.security.session-mode=true",
        "ABIGAIL_MFA_KEY=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
        "ABIGAIL_AUTH_ORIGIN_KEY=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA="
})
@AutoConfigureMockMvc
@Import(SessionHttpApiTest.FixedClock.class)
class SessionHttpApiTest {
    private static final Instant NOW = Instant.parse("2026-11-15T10:00:00Z");
    private static final String PASSWORD = "correct-test-password";
    private static final AtomicInteger NEXT_ADDRESS = new AtomicInteger(10);
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;
    @Autowired AppUserRepository users;
    @Autowired PasswordEncoder passwords;

    @TestConfiguration(proxyBeanMethods = false)
    static class FixedClock {
        @Bean @Primary Clock clockForHttpTests() { return Clock.fixed(NOW, ZoneOffset.UTC); }
    }
    private record CsrfState(MockHttpSession session, String header, String token) {}

    @BeforeEach void seedThrottleForHibernateDdl() {
        Integer count = jdbc.queryForObject("select count(*) from auth_origin_throttle_meta where id='global'", Integer.class);
        if (count != null && count == 0) jdbc.update("insert into auth_origin_throttle_meta (id,entry_count) values ('global',0)");
    }

    @Test void administratorUsesPasswordAndCsrfWhileBasicIsDisabled() throws Exception {
        String address = address();
        AppUser admin = account("ADMIN");
        mvc.perform(get("/api/users").with(origin(address)).with(httpBasic(admin.getUsername(), PASSWORD)))
                .andExpect(status().isUnauthorized());
        mvc.perform(get("/api/me").with(origin(address)).with(httpBasic(admin.getUsername(), PASSWORD)))
                .andExpect(status().isUnauthorized());
        mvc.perform(post("/api/auth/login").with(origin(address)).contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(Map.of("username", admin.getUsername(), "password", PASSWORD))))
                .andExpect(status().isForbidden());
        CsrfState csrf = csrf(address);
        performLogin(address, csrf, admin.getUsername(), "wrong-password", "123456").andExpect(status().isUnauthorized());
        MvcResult response = performLogin(address, csrf, admin.getUsername(), PASSWORD, null)
                .andExpect(status().isOk()).andExpect(header().string("Cache-Control", org.hamcrest.Matchers.containsString("no-store")))
                .andReturn();
        String token = json.readTree(response.getResponse().getContentAsString()).get("token").asText();
        mvc.perform(get("/api/users").with(origin(address)).header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
        // An older client can send its obsolete field; it is ignored, not required.
        performLogin(address, csrf, admin.getUsername(), PASSWORD, "123456").andExpect(status().isOk());
        mvc.perform(post("/api/auth/logout").with(origin(address)).session(csrf.session())
                .header(csrf.header(), csrf.token()).header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());
        mvc.perform(get("/api/me").with(origin(address)).header("Authorization", "Bearer " + token))
                .andExpect(status().isUnauthorized());
    }

    @Test void temporarySellerCanOnlyChangePasswordAndOldSessionIsRevoked() throws Exception {
        String address = address();
        AppUser seller = new AppUser("temporary_" + unique(), passwords.encode(PASSWORD), "SELLER");
        seller.setTemporaryPassword(seller.getPasswordHash(), NOW.plusSeconds(300));
        users.saveAndFlush(seller);
        CsrfState csrf = csrf(address);
        var response = performLogin(address, csrf, seller.getUsername(), PASSWORD, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.mustChangePassword").value(true)).andReturn();
        String token = json.readTree(response.getResponse().getContentAsString()).get("token").asText();
        mvc.perform(get("/api/me").with(origin(address)).header("Authorization", "Bearer " + token))
                .andExpect(status().isOk()).andExpect(jsonPath("$.mustChangePassword").value(true));
        mvc.perform(get("/api/products").with(origin(address)).header("Authorization", "Bearer " + token))
                .andExpect(status().isForbidden());
        mvc.perform(put("/api/account/password").with(origin(address)).session(csrf.session())
                        .header(csrf.header(), csrf.token()).header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("currentPassword", PASSWORD, "newPassword", "new-personal-password"))))
                .andExpect(status().isOk());
        mvc.perform(get("/api/me").with(origin(address)).header("Authorization", "Bearer " + token))
                .andExpect(status().isUnauthorized());
        // A successful authenticated password change can invalidate the previous
        // CSRF state. The Mobile obtains a fresh token before each POST.
        performLogin(address, csrf, seller.getUsername(), "new-personal-password", null)
                .andExpect(status().isForbidden());
        CsrfState fresh = csrf(address);
        performLogin(address, fresh, seller.getUsername(), "new-personal-password", null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.mustChangePassword").value(false));
    }

    @Test void spoofedForwardedAddressesDoNotBypassAnonymousRateLimit() throws Exception {
        String address = address();
        for (int i = 0; i < 30; i++) {
            mvc.perform(get("/api/csrf").with(origin(address)).header("X-Forwarded-For", "203.0.113." + i))
                    .andExpect(status().isOk());
        }
        mvc.perform(get("/api/csrf").with(origin(address)).header("X-Forwarded-For", "203.0.113.99"))
                .andExpect(status().isTooManyRequests());
    }

    private org.springframework.test.web.servlet.ResultActions performLogin(String address, CsrfState csrf,
            String username, String password, String code) throws Exception {
        var fields = new java.util.HashMap<String, String>();
        fields.put("username", username);
        fields.put("password", password);
        if (code != null) fields.put("code", code);
        return mvc.perform(post("/api/auth/login").with(origin(address)).session(csrf.session())
                .header(csrf.header(), csrf.token()).contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(fields)));
    }

    private CsrfState csrf(String address) throws Exception {
        var response = mvc.perform(get("/api/csrf").with(origin(address))).andExpect(status().isOk()).andReturn();
        var body = json.readTree(response.getResponse().getContentAsString());
        return new CsrfState((MockHttpSession) response.getRequest().getSession(false),
                body.get("headerName").asText(), body.get("token").asText());
    }

    private AppUser account(String role) {
        return users.saveAndFlush(new AppUser("http_" + unique(), passwords.encode(PASSWORD), role));
    }
    private static String unique() { return UUID.randomUUID().toString().replace("-", ""); }
    private static String address() { return "192.0.2." + NEXT_ADDRESS.getAndIncrement(); }
    private static RequestPostProcessor origin(String value) {
        return request -> { request.setRemoteAddr(value); return request; };
    }
}
