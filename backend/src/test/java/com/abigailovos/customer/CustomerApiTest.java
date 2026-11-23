package com.abigailovos.customer;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
class CustomerApiTest {
    @Autowired MockMvc mvc;
    @Autowired CustomerRepository customers;

    @BeforeEach void clear() { customers.deleteAll(); }

    @Test void anonymousAccessIsDenied() throws Exception {
        mvc.perform(get("/api/customers")).andExpect(status().isUnauthorized());
    }

    @Test @WithMockUser(roles = "SELLER")
    void sellerCanReadCustomersButCannotCreateOutsideSale() throws Exception {
        Customer customer = customers.saveAndFlush(new Customer("Ana", "12345"));
        mvc.perform(post("/api/customers").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ana\"}")) .andExpect(status().isForbidden());
        mvc.perform(get("/api/customers/" + customer.getId())).andExpect(status().isOk())
                .andExpect(jsonPath("$.phone").value("12345"));
        mvc.perform(get("/api/customers")).andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("Ana"));
    }

    @Test @WithMockUser(roles = "OTHER")
    void otherRolesCannotReadOrWrite() throws Exception {
        mvc.perform(get("/api/customers")).andExpect(status().isForbidden());
        mvc.perform(post("/api/customers").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ana\"}"))
                .andExpect(status().isForbidden());
    }

    @Test void adminCanReadButCannotCreateOrUpdateCustomer() throws Exception {
        Customer customer = customers.saveAndFlush(new Customer("Ana", "123"));
        String path = "/api/customers/" + customer.getId();
        String data = "{\"name\":\" Maria \",\"phone\":\"456\"}";
        mvc.perform(put(path).with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data)).andExpect(status().isForbidden());
        mvc.perform(put(path).with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data)).andExpect(status().isForbidden());
        mvc.perform(post("/api/customers").with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data)).andExpect(status().isForbidden());
        mvc.perform(get(path).with(user("admin").roles("ADMIN"))).andExpect(status().isOk()).andExpect(jsonPath("$.name").value("Ana"));
        mvc.perform(get("/api/customers").with(user("admin").roles("ADMIN"))).andExpect(status().isOk()).andExpect(jsonPath("$[0].name").value("Ana"));
    }
}
