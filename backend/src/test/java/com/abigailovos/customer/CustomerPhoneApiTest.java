package com.abigailovos.customer;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import static com.abigailovos.testutil.TestPhones.next;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(properties = "spring.datasource.url=jdbc:h2:mem:phone_scope;MODE=MySQL;DB_CLOSE_DELAY=-1")
@AutoConfigureMockMvc
class CustomerPhoneApiTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;

    @Test void duplicateOnCreateAndEditIsRejectedWithoutChangingHistory() throws Exception {
        String firstPhone = next();
        String secondPhone = next();
        String product = product();
        String firstId = UUID.randomUUID().toString();
        String first = request(firstId, product, "Cliente A", firstPhone);
        String firstResponse = mvc.perform(post("/api/sales").with(user("ana").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(first)).andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        String customerId = json.readTree(firstResponse).get("customerId").asText();
        mvc.perform(post("/api/sales").with(user("ana").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(first)).andExpect(status().isCreated());
        String duplicateId = UUID.randomUUID().toString();
        mvc.perform(post("/api/sales").with(user("bia").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(request(duplicateId, product, "Outro nome", "+258 " + firstPhone)))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("CUSTOMER_PHONE_EXISTS"));
        assertThat(jdbc.queryForObject("select count(*) from sales where id = ?", Integer.class, duplicateId)).isZero();
        assertThat(jdbc.queryForObject("select count(*) from audit_events where target_id = ?", Integer.class, duplicateId)).isZero();

        String secondId = UUID.randomUUID().toString();
        String second = mvc.perform(post("/api/sales").with(user("bia").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(request(secondId, product, "Cliente A", secondPhone)))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String otherCustomer = json.readTree(second).get("customerId").asText();
        mvc.perform(put("/api/customers/" + otherCustomer).with(user("bia").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Alterado\",\"phone\":\"00258" + firstPhone + "\"}"))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("CUSTOMER_PHONE_EXISTS"));
        mvc.perform(get("/api/customers/" + otherCustomer).with(user("ana").roles("SELLER")))
                .andExpect(jsonPath("$.name").value("Cliente A")).andExpect(jsonPath("$.phone").value(secondPhone))
                .andExpect(jsonPath("$.phoneKey").doesNotExist());
        assertThat(jdbc.queryForObject("select customer_id from sales where id = ?", String.class, firstId)).isEqualTo(customerId);
        assertThat(jdbc.queryForObject("select count(*) from audit_events where target_id = ? and action = 'CUSTOMER_UPDATED'", Integer.class, otherCustomer)).isZero();
        mvc.perform(post("/api/sales").with(user("ana").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(request(UUID.randomUUID().toString(), product, "Sem telefone", "")))
                .andExpect(status().isBadRequest());
        mvc.perform(get("/api/stock/" + product).with(user("ana").roles("SELLER")))
                .andExpect(jsonPath("$.quantity").value(5)).andExpect(jsonPath("$.reserved").value(2));
    }

    @Test void concurrentDifferentProductsCannotCreateSamePhone() throws Exception {
        String firstProduct = product();
        String secondProduct = product();
        String phone = next();
        String firstId = UUID.randomUUID().toString();
        String secondId = UUID.randomUUID().toString();
        String first = request(firstId, firstProduct, "A", phone);
        String second = request(secondId, secondProduct, "B", "+258 " + phone);
        var start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(2)) {
            var a = executor.submit(() -> { start.await(); return submit(first); });
            var b = executor.submit(() -> { start.await(); return submit(second); });
            start.countDown();
            assertThat(List.of(a.get(30, TimeUnit.SECONDS), b.get(30, TimeUnit.SECONDS))).containsExactlyInAnyOrder(201, 409);
        }
        assertThat(jdbc.queryForObject("select count(*) from customers where phone_key = ?", Integer.class, "+258" + phone)).isEqualTo(1);
        assertThat(jdbc.queryForObject("select count(*) from sales where id in (?, ?)", Integer.class, firstId, secondId)).isEqualTo(1);
        assertThat(jdbc.queryForObject("select count(*) from audit_events where target_id in (?, ?) and action = 'SALE_CREATED'", Integer.class, firstId, secondId)).isEqualTo(1);
        assertThat(jdbc.queryForObject("select count(*) from sale_items where sale_id in (?, ?)", Integer.class, firstId, secondId)).isEqualTo(1);
        mvc.perform(get("/api/stock/" + firstProduct).with(user("ana").roles("SELLER")))
                .andExpect(jsonPath("$.quantity").value(5));
        mvc.perform(get("/api/stock/" + secondProduct).with(user("ana").roles("SELLER")))
                .andExpect(jsonPath("$.quantity").value(5));
    }

    private String product() throws Exception {
        String result = mvc.perform(post("/api/products").with(user("admin").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Produto\",\"unit\":\"unidade\",\"price\":2}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String id = json.readTree(result).get("id").asText();
        mvc.perform(post("/api/stock/movements").with(user("ana").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"operationId\":\"" + UUID.randomUUID() + "\",\"productId\":\"" + id
                        + "\",\"type\":\"ENTRY\",\"direction\":\"INCREASE\",\"quantity\":5,\"reason\":\"teste\"}"))
                .andExpect(status().isCreated());
        return id;
    }

    private String request(String id, String product, String name, String phone) throws Exception {
        return json.writeValueAsString(java.util.Map.of("id", id, "customer", java.util.Map.of("name", name, "phone", phone),
                "items", List.of(java.util.Map.of("productId", product, "quantity", 1, "expectedUnitPrice", 2)),
                "deliverNow", false, "paid", false));
    }

    private int submit(String request) throws Exception {
        return mvc.perform(post("/api/sales").with(user("ana").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(request)).andReturn().getResponse().getStatus();
    }
}
