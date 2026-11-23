package com.abigailovos.security;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(properties = "abigail.security.require-https=true")
@AutoConfigureMockMvc
class HttpsPolicyTest {
    @Autowired MockMvc mvc;

    @Test
    @WithMockUser(roles = "SELLER")
    void insecureRequestsAreNotServed() throws Exception {
        mvc.perform(get("/api/me")).andExpect(status().is3xxRedirection())
                .andExpect(header().string("Location", org.hamcrest.Matchers.startsWith("https://")));
    }

    @Test
    @WithMockUser(roles = "SELLER")
    void secureRequestsAreAllowedAndGetHsts() throws Exception {
        mvc.perform(get("/api/me").secure(true)).andExpect(status().isOk())
                .andExpect(header().exists("Strict-Transport-Security"));
    }
}
