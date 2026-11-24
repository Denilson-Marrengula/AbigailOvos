package com.abigailovos.security;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import static org.assertj.core.api.Assertions.assertThat;
import static com.abigailovos.testutil.TestPhones.next;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest @AutoConfigureMockMvc
class AccountApiTest {
    @Autowired MockMvc mvc;
    @Autowired AppUserRepository users;
    @Autowired PasswordEncoder encoder;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;

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
                .andExpect(status().isOk()).andExpect(jsonPath("$.roles[0]").value("ROLE_SELLER"))
                .andExpect(jsonPath("$.mustChangePassword").value(true));
        mvc.perform(get("/api/products").with(httpBasic(username, password))).andExpect(status().isForbidden());
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

    @Test void deletingSellerPreservesHistoryAndPreventsUsernameReuse() throws Exception {
        String name = "hist_" + java.util.UUID.randomUUID().toString().replace("-", "");
        String password = "test-password-123";
        org.springframework.test.web.servlet.request.RequestPostProcessor isolatedAddress = request -> {
            request.setRemoteAddr("198.51.100.201");
            return request;
        };
        String created = mvc.perform(post("/api/users").with(user("admin").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"username\":\""+name+"\",\"password\":\""+password+"\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String sellerId = json.readTree(created).get("id").asText();
        String product = mvc.perform(post("/api/products").with(user("admin").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Ovos\",\"unit\":\"bandeja\",\"price\":2}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String productId = json.readTree(product).get("id").asText();
        String movementId = java.util.UUID.randomUUID().toString();
        mvc.perform(post("/api/stock/movements").with(user(name).roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"operationId\":\""+movementId+"\",\"productId\":\""+productId+"\",\"type\":\"ENTRY\",\"direction\":\"INCREASE\",\"quantity\":2,\"reason\":\"teste\"}"))
                .andExpect(status().isCreated());
        String saleId = java.util.UUID.randomUUID().toString();
        mvc.perform(post("/api/sales").with(user(name).roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"id\":\""+saleId+"\",\"customer\":{\"name\":\"Cliente teste\",\"phone\":\"" + next() + "\"},\"items\":[{\"productId\":\""+productId+"\",\"quantity\":1,\"expectedUnitPrice\":2}],\"deliverNow\":true,\"paid\":false}"))
                .andExpect(status().isCreated());
        var csrfResponse = mvc.perform(get("/api/csrf").with(httpBasic(name, password)))
                .andExpect(status().isOk()).andReturn();
        var csrfBody = json.readTree(csrfResponse.getResponse().getContentAsString());
        var priorSession = (org.springframework.mock.web.MockHttpSession) csrfResponse.getRequest().getSession(false);
        mvc.perform(delete("/api/users/"+sellerId).with(user(name).roles("SELLER")).with(csrf())).andExpect(status().isForbidden());
        mvc.perform(delete("/api/users/"+sellerId).with(user("admin").roles("ADMIN"))).andExpect(status().isForbidden());
        mvc.perform(delete("/api/users/"+sellerId).with(user("admin").roles("ADMIN")).with(csrf())).andExpect(status().isNoContent());
        assertThat(users.findById(sellerId)).isEmpty();
        mvc.perform(get("/api/me").with(isolatedAddress).with(httpBasic(name, password))).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/me").session(priorSession).with(isolatedAddress).with(httpBasic(name, password))).andExpect(status().isUnauthorized());
        mvc.perform(post("/api/sales").session(priorSession).with(isolatedAddress).with(httpBasic(name, password))
                .header(csrfBody.get("headerName").asText(), csrfBody.get("token").asText())
                .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isUnauthorized());
        // Other API tests share this in-memory database and may leave unrelated sales.
        assertThat(jdbc.queryForObject("select seller from sales where id=?", String.class, saleId)).isEqualTo(name);
        mvc.perform(get("/api/stock/"+productId+"/movements").with(user("admin").roles("ADMIN")))
                .andExpect(jsonPath("$[?(@.id == '"+movementId+"')].administrator").value(org.hamcrest.Matchers.hasItem(name)));
        assertThat(jdbc.queryForObject("select count(*) from audit_events where target_id=? and action='SELLER_DELETED'", Integer.class, sellerId)).isEqualTo(1);
        mvc.perform(post("/api/users").with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\":\""+name.toUpperCase(java.util.Locale.ROOT)+"\",\"password\":\""+password+"\"}"))
                .andExpect(status().isConflict());
        mvc.perform(delete("/api/users/"+sellerId).with(user("admin").roles("ADMIN")).with(csrf())).andExpect(status().isNotFound());
    }

    @Test void adminAccountCannotBeDeleted() throws Exception {
        String suffix = java.util.UUID.randomUUID().toString().replace("-", "");
        AppUser admin = users.saveAndFlush(new AppUser("adm_"+suffix, encoder.encode("test-password-123"), "ADMIN"));
        mvc.perform(delete("/api/users/"+admin.getId()).with(user("admin").roles("ADMIN")).with(csrf()))
                .andExpect(status().isForbidden());
        assertThat(users.findById(admin.getId())).isPresent();
    }

    @Test void concurrentAccountCreationReservesUsernameOnlyOnce() throws Exception {
        String name = "race_" + java.util.UUID.randomUUID().toString().replace("-", "");
        var start = new java.util.concurrent.CountDownLatch(1);
        var executor = java.util.concurrent.Executors.newFixedThreadPool(2);
        try {
            java.util.concurrent.Callable<Integer> create = () -> {
                start.await();
                return mvc.perform(post("/api/users").with(user("admin").roles("ADMIN")).with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\""+name+"\",\"password\":\"test-password-123\"}"))
                        .andReturn().getResponse().getStatus();
            };
            var first = executor.submit(create);
            var second = executor.submit(create);
            start.countDown();
            assertThat(java.util.List.of(first.get(), second.get())).containsExactlyInAnyOrder(201, 409);
            assertThat(jdbc.queryForObject("select count(*) from reserved_usernames where username_key=?", Integer.class, name)).isEqualTo(1);
            assertThat(jdbc.queryForObject("select count(*) from app_users where username=?", Integer.class, name)).isEqualTo(1);
        } finally {
            executor.shutdownNow();
        }
    }

    @Test void concurrentProfileChangeCannotRestoreDeletedAccount() throws Exception {
        String name = "race_" + java.util.UUID.randomUUID().toString().replace("-", "");
        String created = mvc.perform(post("/api/users").with(user("admin").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\":\""+name+"\",\"password\":\"test-password-123\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String id = json.readTree(created).get("id").asText();
        var start = new java.util.concurrent.CountDownLatch(1);
        var executor = java.util.concurrent.Executors.newFixedThreadPool(2);
        try {
            var update = executor.submit(() -> {
                start.await();
                return mvc.perform(put("/api/users/"+id+"/profile").with(user("admin").roles("ADMIN")).with(csrf())
                        .contentType(MediaType.APPLICATION_JSON).content("{\"displayName\":\"Novo nome\"}"))
                        .andReturn().getResponse().getStatus();
            });
            var delete = executor.submit(() -> {
                start.await();
                return mvc.perform(delete("/api/users/"+id).with(user("admin").roles("ADMIN")).with(csrf()))
                        .andReturn().getResponse().getStatus();
            });
            start.countDown();
            assertThat(delete.get()).isEqualTo(204);
            assertThat(update.get()).isIn(200, 404);
            assertThat(users.findById(id)).isEmpty();
            assertThat(jdbc.queryForObject("select count(*) from reserved_usernames where username_key=?", Integer.class, name)).isEqualTo(1);
        } finally {
            executor.shutdownNow();
        }
    }
}
