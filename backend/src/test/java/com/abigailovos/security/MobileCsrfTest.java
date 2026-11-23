package com.abigailovos.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class MobileCsrfTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;

    @Test
    void anonymousClientCannotObtainToken() throws Exception {
        mvc.perform(get("/api/csrf")).andExpect(status().isUnauthorized());
    }

    @Test
    @WithMockUser(roles = "SELLER")
    void authenticatedClientCanUseTokenWithSameSession() throws Exception {
        var response = mvc.perform(get("/api/csrf"))
                .andExpect(status().isOk()).andReturn();
        var body = json.readTree(response.getResponse().getContentAsString());
        var session = (MockHttpSession) response.getRequest().getSession(false);
        mvc.perform(post("/api/sales").session(session)
                        .header(body.get("headerName").asText(), body.get("token").asText())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());
        mvc.perform(post("/api/sales").contentType(MediaType.APPLICATION_JSON)
                        .header(body.get("headerName").asText(), body.get("token").asText())
                        .content("{}"))
                .andExpect(status().isForbidden());
    }
}
