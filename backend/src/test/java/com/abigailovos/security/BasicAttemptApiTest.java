package com.abigailovos.security;

import java.util.UUID;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest @AutoConfigureMockMvc
class BasicAttemptApiTest {
    @Autowired MockMvc mvc;
    @Autowired AppUserRepository users;
    @Autowired PasswordEncoder encoder;

    @Test void limitsFailuresAcrossAccountsAndIgnoresForgedForwardedAddress() throws Exception {
        String username = "limiter_" + UUID.randomUUID().toString().replace("-", "");
        String password = "test-password-123";
        users.saveAndFlush(new AppUser(username, encoder.encode(password), "SELLER"));
        for (int i = 0; i < 5; i++) {
            mvc.perform(get("/api/me").with(request -> { request.setRemoteAddr("192.0.2.41"); return request; })
                    .header("X-Forwarded-For", "203.0.113." + i)
                    .with(httpBasic(username, "wrong-password")))
                    .andExpect(status().isUnauthorized());
        }
        mvc.perform(get("/api/me").with(request -> { request.setRemoteAddr("192.0.2.41"); return request; })
                .header("X-Forwarded-For", "203.0.113.99").with(httpBasic(username, password)))
                .andExpect(status().isTooManyRequests()).andExpect(header().exists("Retry-After"));
        mvc.perform(get("/api/me").with(request -> { request.setRemoteAddr("192.0.2.42"); return request; })
                .with(httpBasic(username, password))).andExpect(status().isOk());
        mvc.perform(get("/api/me").with(request -> { request.setRemoteAddr("192.0.2.41"); return request; }))
                .andExpect(status().isUnauthorized());
    }

    @Test void springBasicHeaderVariantsCannotBypassTheLimit() throws Exception {
        String token = Base64.getEncoder().encodeToString("nobody:wrong".getBytes(StandardCharsets.UTF_8));
        for (int i = 0; i < 5; i++) {
            mvc.perform(get("/api/me").with(request -> { request.setRemoteAddr("192.0.2.43"); return request; })
                    .header("Authorization", "bAsIc!" + token))
                    .andExpect(status().isUnauthorized());
        }
        mvc.perform(get("/api/me").with(request -> { request.setRemoteAddr("192.0.2.43"); return request; })
                .header("Authorization", "  Basic " + token))
                .andExpect(status().isTooManyRequests());
    }
}
