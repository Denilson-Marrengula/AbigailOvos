package com.abigailovos.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(properties = "spring.datasource.url=jdbc:h2:mem:password_recovery;MODE=MySQL;DB_CLOSE_DELAY=-1")
@AutoConfigureMockMvc
class SellerPasswordRecoveryTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;
    @Autowired AppUserRepository users;
    @Autowired PasswordEncoder passwords;
    @Autowired JdbcTemplate jdbc;

    @Test void newlyCreatedSellerMustChangeInitialPasswordBeforeWorking() throws Exception {
        String name = "new_" + UUID.randomUUID().toString().replace("-", "");
        String initial = "first-test-password";
        String replacement = "different-test-password";
        String created = mvc.perform(post("/api/users").with(user("admin").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(java.util.Map.of("username", name, "password", initial))))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String id = json.readTree(created).get("id").asText();
        AppUser account = users.findById(id).orElseThrow();
        assertThat(account.mustChangePassword()).isTrue();
        assertThat(account.temporaryPasswordExpiresAt()).isAfter(Instant.now());
        mvc.perform(get("/api/me").with(httpBasic(name, initial)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.mustChangePassword").value(true));
        mvc.perform(get("/api/products").with(httpBasic(name, initial))).andExpect(status().isForbidden());
        mvc.perform(put("/api/account/password").with(httpBasic(name, initial)).with(csrf())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(java.util.Map.of("currentPassword", initial, "newPassword", replacement))))
                .andExpect(status().isOk());
        AppUser updated = users.findById(id).orElseThrow();
        assertThat(passwords.matches(initial, updated.getPasswordHash())).isFalse();
        assertThat(passwords.matches(replacement, updated.getPasswordHash())).isTrue();
        mvc.perform(get("/api/products").with(httpBasic(name, replacement))).andExpect(status().isOk());
    }

    @Test void resetRevokesOldPasswordAndRestrictsTemporaryCredentialUntilChange() throws Exception {
        String name = "recover_" + UUID.randomUUID().toString().replace("-", "");
        String oldPassword = "old-test-password";
        String newPassword = "new-test-password";
        String created = mvc.perform(post("/api/users").with(user("admin").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"username\":\"" + name + "\",\"password\":\"" + oldPassword + "\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String id = json.readTree(created).get("id").asText();
        String path = "/api/users/" + id + "/password-reset";
        var beforeReset = mvc.perform(get("/api/csrf").with(httpBasic(name, oldPassword)))
                .andExpect(status().isOk()).andReturn();
        var priorSession = (org.springframework.mock.web.MockHttpSession) beforeReset.getRequest().getSession(false);
        var csrfToken = json.readTree(beforeReset.getResponse().getContentAsString());
        mvc.perform(patch(path).with(user("admin").roles("ADMIN"))).andExpect(status().isForbidden());
        mvc.perform(patch(path).with(user(name).roles("SELLER")).with(csrf())).andExpect(status().isForbidden());
        String response = mvc.perform(patch(path).with(user("admin").roles("ADMIN")).with(csrf()))
                .andExpect(status().isOk()).andExpect(header().string("Cache-Control", "no-store"))
                .andReturn().getResponse().getContentAsString();
        String temporary = json.readTree(response).get("temporaryPassword").asText();
        Instant expires = Instant.parse(json.readTree(response).get("expiresAt").asText());
        assertThat(temporary).hasSize(32).doesNotContain(oldPassword, newPassword);
        assertThat(expires).isAfter(Instant.now()).isBefore(Instant.now().plusSeconds(25 * 3600));
        AppUser account = users.findById(id).orElseThrow();
        assertThat(account.getPasswordHash()).doesNotContain(temporary);
        assertThat(passwords.matches(temporary, account.getPasswordHash())).isTrue();
        assertThat(account.mustChangePassword()).isTrue();
        assertThat(jdbc.queryForObject("select actor from audit_events where target_id = ? and action = 'SELLER_PASSWORD_RESET'", String.class, id)).isEqualTo("admin");
        assertThat(jdbc.queryForObject("select detail from audit_events where target_id = ? and action = 'SELLER_PASSWORD_RESET'", String.class, id)).doesNotContain(temporary);

        mvc.perform(get("/api/me").with(httpBasic(name, oldPassword))).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/me").session(priorSession).with(httpBasic(name, oldPassword))).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/me").with(httpBasic(name, temporary))).andExpect(status().isOk())
                .andExpect(jsonPath("$.mustChangePassword").value(true));
        mvc.perform(get("/api/csrf").with(httpBasic(name, temporary))).andExpect(status().isOk());
        mvc.perform(get("/api/products").with(httpBasic(name, temporary))).andExpect(status().isForbidden());
        mvc.perform(get("/api/sales").with(httpBasic(name, temporary))).andExpect(status().isForbidden());
        mvc.perform(post("/api/sales").with(httpBasic(name, temporary)).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isForbidden());
        mvc.perform(post("/api/sales").session(priorSession).with(httpBasic(name, temporary))
                .header(csrfToken.get("headerName").asText(), csrfToken.get("token").asText())
                .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isForbidden());
        String body = json.writeValueAsString(java.util.Map.of("currentPassword", temporary, "newPassword", newPassword));
        mvc.perform(put("/api/account/password").with(httpBasic(name, temporary)).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isForbidden());
        mvc.perform(put("/api/account/password").with(httpBasic(name, temporary)).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(java.util.Map.of("currentPassword", temporary, "newPassword", temporary))))
                .andExpect(status().isBadRequest());
        mvc.perform(put("/api/account/password").with(httpBasic(name, temporary)).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isOk());
        mvc.perform(get("/api/me").with(httpBasic(name, temporary))).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/me").with(httpBasic(name, newPassword))).andExpect(status().isOk())
                .andExpect(jsonPath("$.mustChangePassword").value(false));
        mvc.perform(get("/api/products").with(httpBasic(name, newPassword))).andExpect(status().isOk());
        assertThat(users.findById(id).orElseThrow().temporaryPasswordExpiresAt()).isNull();
        assertThat(jdbc.queryForObject("select actor from audit_events where target_id = ? and action = 'PASSWORD_CHANGED'", String.class, id)).isEqualTo(name);
    }

    @Test void resetOnlyAppliesToEnabledSellersAndExpires() throws Exception {
        String suffix = UUID.randomUUID().toString().replace("-", "");
        AppUser admin = users.saveAndFlush(new AppUser("admin_" + suffix, passwords.encode("test-password-123"), "ADMIN"));
        AppUser seller = users.saveAndFlush(new AppUser("seller_" + suffix, passwords.encode("test-password-123"), "SELLER"));
        mvc.perform(patch("/api/users/" + admin.getId() + "/password-reset").with(user("admin").roles("ADMIN")).with(csrf()))
                .andExpect(status().isForbidden());
        mvc.perform(patch("/api/users/" + seller.getId() + "/status").with(user("admin").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":false}")).andExpect(status().isOk());
        mvc.perform(patch("/api/users/" + seller.getId() + "/password-reset").with(user("admin").roles("ADMIN")).with(csrf()))
                .andExpect(status().isConflict());
        mvc.perform(patch("/api/users/" + seller.getId() + "/status").with(user("admin").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":true}")).andExpect(status().isOk());
        String response = mvc.perform(patch("/api/users/" + seller.getId() + "/password-reset").with(user("admin").roles("ADMIN")).with(csrf()))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String temporary = json.readTree(response).get("temporaryPassword").asText();
        jdbc.update("update app_users set temporary_password_expires_at = ? where id = ?",
                Timestamp.from(Instant.now().minusSeconds(1)), seller.getId());
        mvc.perform(get("/api/me").with(httpBasic(seller.getUsername(), temporary))).andExpect(status().isUnauthorized());
    }
}
