package com.abigailovos.customer;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import static org.assertj.core.api.Assertions.assertThat;
import static com.abigailovos.testutil.TestPhones.next;
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
    @Autowired JdbcTemplate jdbc;

    @BeforeEach void clear() { customers.deleteAll(); }

    @Test void anonymousAccessIsDenied() throws Exception {
        mvc.perform(get("/api/customers")).andExpect(status().isUnauthorized());
    }

    @Test @WithMockUser(roles = "SELLER")
    void sellerCanReadCustomersButCannotCreateOutsideSale() throws Exception {
        String phone = next();
        Customer customer = customers.saveAndFlush(new Customer("Ana", phone));
        mvc.perform(post("/api/customers").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ana\"}")) .andExpect(status().isForbidden());
        mvc.perform(get("/api/customers/" + customer.getId())).andExpect(status().isOk())
                .andExpect(jsonPath("$.phone").value(phone));
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

    @Test void onlySellerCanUpdateARegisteredCustomer() throws Exception {
        Customer customer = customers.saveAndFlush(new Customer("Ana", next()));
        String path = "/api/customers/" + customer.getId();
        String updatedPhone = next();
        String data = "{\"name\":\" Maria \",\"phone\":\"" + updatedPhone + "\"}";
        mvc.perform(put(path).with(user("seller").roles("SELLER")).contentType(MediaType.APPLICATION_JSON).content(data)).andExpect(status().isForbidden());
        mvc.perform(put(path).with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data)).andExpect(status().isForbidden());
        mvc.perform(put(path).with(user("other").roles("OTHER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data)).andExpect(status().isForbidden());
        mvc.perform(post("/api/customers").with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data)).andExpect(status().isForbidden());
        mvc.perform(put(path).with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data))
                .andExpect(status().isOk()).andExpect(jsonPath("$.id").value(customer.getId()))
                .andExpect(jsonPath("$.name").value("Maria")).andExpect(jsonPath("$.phone").value(updatedPhone));
        mvc.perform(get(path).with(user("admin").roles("ADMIN"))).andExpect(status().isOk()).andExpect(jsonPath("$.name").value("Maria"));
        mvc.perform(get(path).with(user("outro_vendedor").roles("SELLER"))).andExpect(status().isOk()).andExpect(jsonPath("$.name").value("Maria"));
        assertThat(jdbc.queryForObject("select count(*) from audit_events where target_id=? and action='CUSTOMER_UPDATED' and actor='seller'", Integer.class, customer.getId())).isEqualTo(1);
        assertThat(jdbc.queryForObject("select detail from audit_events where target_id=? and action='CUSTOMER_UPDATED'", String.class, customer.getId())).isEqualTo("fields=name,phone");
    }

    @Test void updatingCustomerRequiresAValidPhone() throws Exception {
        String originalPhone = next();
        Customer customer = customers.saveAndFlush(new Customer("Ana", originalPhone));
        String path = "/api/customers/" + customer.getId();
        mvc.perform(put(path).with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"  \",\"phone\":\"123\"}")).andExpect(status().isBadRequest());
        mvc.perform(put(path).with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ana\",\"phone\":\"" + "1".repeat(41) + "\"}")).andExpect(status().isBadRequest());
        mvc.perform(put("/api/customers/" + java.util.UUID.randomUUID()).with(user("seller").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Ana\"}")).andExpect(status().isNotFound());
        mvc.perform(put(path).with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ana\",\"phone\":\"   \"}"))
                .andExpect(status().isBadRequest());
        assertThat(customers.findById(customer.getId()).orElseThrow().getPhone()).isEqualTo(originalPhone);
    }
}
