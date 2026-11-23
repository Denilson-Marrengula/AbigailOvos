package com.abigailovos.security;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest @AutoConfigureMockMvc
class AccountApiTest {
    @Autowired MockMvc mvc;
    @Autowired AppUserRepository users;
    @Autowired PasswordEncoder encoder;

    @Test @WithMockUser(roles = "ADMIN")
    void createsSellerWithHashedPasswordAndAuthenticates() throws Exception {
        String username = "seller_" + java.util.UUID.randomUUID().toString().replace("-", "");
        String password = "safe-test-password";
        mvc.perform(post("/api/users").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\":\"" + username + "\",\"password\":\"" + password + "\"}"))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.role").value("SELLER"))
                .andExpect(jsonPath("$.passwordHash").doesNotExist());
        assertThat(encoder.matches(password, users.findByUsername(username).orElseThrow().getPasswordHash())).isTrue();
        mvc.perform(get("/api/me").with(httpBasic(username, password)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.roles[0]").value("ROLE_SELLER"));
    }

    @Test @WithMockUser(roles = "SELLER")
    void sellerCannotCreateAccounts() throws Exception {
        mvc.perform(post("/api/users").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\":\"newuser\",\"password\":\"safe-test-password\"}"))
                .andExpect(status().isForbidden());
    }

    @Test @WithMockUser(roles = "ADMIN")
    void createsSellerWithProfileInOneRequest() throws Exception {
        String username = "seller_" + java.util.UUID.randomUUID().toString().replace("-", "");
        mvc.perform(post("/api/users").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\":\"" + username + "\",\"password\":\"safe-test-password\",\"displayName\":\" Maria \",\"phone\":\"123\"}"))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.displayName").value("Maria"))
                .andExpect(jsonPath("$.phone").value("123"));
        assertThat(users.findByUsername(username).orElseThrow().getDisplayName()).isEqualTo("Maria");
        mvc.perform(post("/api/users").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\":\"another_" + username + "\",\"password\":\"safe-test-password\",\"displayName\":\" \"}"))
                .andExpect(status().isBadRequest());
    }

    @Test @WithMockUser(roles = "ADMIN")
    void rejectsShortPasswords() throws Exception {
        mvc.perform(post("/api/users").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\":\"newuser\",\"password\":\"short\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void actualCredentialsEnforceBothRoles() throws Exception {
        String suffix = java.util.UUID.randomUUID().toString().replace("-", "");
        String password = "test-password-123";
        String admin = "admin_" + suffix;
        String seller = "seller_" + suffix;
        users.saveAndFlush(new AppUser(admin, encoder.encode(password), "ADMIN"));
        users.saveAndFlush(new AppUser(seller, encoder.encode(password), "SELLER"));
        mvc.perform(get("/api/me").with(httpBasic(admin, password)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.roles[0]").value("ROLE_ADMIN"));
        mvc.perform(get("/api/users").with(httpBasic(admin, password))).andExpect(status().isOk());
        mvc.perform(get("/api/me").with(httpBasic(seller, password)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.roles[0]").value("ROLE_SELLER"));
        mvc.perform(get("/api/users").with(httpBasic(seller, password))).andExpect(status().isForbidden());
        mvc.perform(get("/api/me").with(httpBasic(admin, "incorrect"))).andExpect(status().isUnauthorized());
    }

    @Test
    void disabledSellerCannotAuthenticateAndOnlyAdminCanChangeStatus() throws Exception {
        String suffix = java.util.UUID.randomUUID().toString().replace("-", "");
        String password = "test-password-123";
        String admin = "admin_" + suffix;
        String seller = "seller_" + suffix;
        AppUser adminUser = users.saveAndFlush(new AppUser(admin, encoder.encode(password), "ADMIN"));
        AppUser sellerUser = users.saveAndFlush(new AppUser(seller, encoder.encode(password), "SELLER"));
        String path = "/api/users/" + sellerUser.getId() + "/status";
        var csrfSession = (org.springframework.mock.web.MockHttpSession) mvc.perform(
                get("/api/csrf").with(httpBasic(seller, password)))
                .andExpect(status().isOk()).andReturn().getRequest().getSession(false);
        mvc.perform(patch(path).with(httpBasic(seller, password)).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":false}"))
                .andExpect(status().isForbidden());
        mvc.perform(patch("/api/users/" + adminUser.getId() + "/status").with(httpBasic(admin, password)).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":false}"))
                .andExpect(status().isForbidden());
        mvc.perform(patch(path).with(httpBasic(admin, password)).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":false}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.enabled").value(false));
        mvc.perform(get("/api/me").with(httpBasic(seller, password))).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/me").session(csrfSession).with(httpBasic(seller, password)))
                .andExpect(status().isUnauthorized());
        mvc.perform(patch(path).with(httpBasic(admin, password)).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":true}"))
                .andExpect(status().isOk());
        mvc.perform(get("/api/me").with(httpBasic(seller, password))).andExpect(status().isOk());
    }

    @Test void onlyAdminCanUpdateSellerProfile() throws Exception {
        String suffix = java.util.UUID.randomUUID().toString();
        AppUser seller = users.saveAndFlush(new AppUser("seller_" + suffix, encoder.encode("test-password-123"), "SELLER"));
        AppUser admin = users.saveAndFlush(new AppUser("admin_" + suffix, encoder.encode("test-password-123"), "ADMIN"));
        String data = "{\"displayName\":\" Maria \",\"phone\":\"123\"}";
        String path = "/api/users/" + seller.getId() + "/profile";
        mvc.perform(put(path).with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data)).andExpect(status().isForbidden());
        mvc.perform(put(path).with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data))
                .andExpect(status().isOk()).andExpect(jsonPath("$.displayName").value("Maria")).andExpect(jsonPath("$.phone").value("123"));
        mvc.perform(put("/api/users/" + admin.getId() + "/profile").with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data)).andExpect(status().isForbidden());
        mvc.perform(put(path).with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content("{\"displayName\":\" \"}"))
                .andExpect(status().isBadRequest());
    }
}
