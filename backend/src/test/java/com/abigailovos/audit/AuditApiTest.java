package com.abigailovos.audit;

import com.abigailovos.customer.Customer;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.EntityManager;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;
import static com.abigailovos.testutil.TestPhones.next;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest @AutoConfigureMockMvc
class AuditApiTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;
    @Autowired TransactionTemplate transactions;
    @Autowired EntityManager em;
    @Autowired AuditLog audit;

    @Test void auditIsRestrictedAndRecordsSuccessfulChangesWithoutSecretsOrRetryDuplicates() throws Exception {
        String username = "audit_" + UUID.randomUUID().toString().replace("-", "");
        String password = "password-secret-test";
        String sellerBody = "{\"username\":\"" + username + "\",\"password\":\"" + password
                + "\",\"displayName\":\"Nome privado\",\"phone\":\"841234567\"}";
        String seller = mvc.perform(post("/api/users").with(user("admin-audit").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(sellerBody)).andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        String sellerId = json.readTree(seller).get("id").asText();
        mvc.perform(patch("/api/users/" + sellerId + "/status").with(user("admin-audit").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":false}")).andExpect(status().isOk());
        assertThat(count(sellerId, "SELLER_CREATED")).isEqualTo(1);
        assertThat(count(sellerId, "SELLER_STATUS_SET")).isEqualTo(1);

        String product = mvc.perform(post("/api/products").with(user("admin-audit").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Ovos\",\"unit\":\"unidade\",\"price\":2}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String productId = json.readTree(product).get("id").asText();
        assertThat(count(productId, "PRODUCT_CREATED")).isEqualTo(1);
        String operation = UUID.randomUUID().toString();
        String movement = "{\"operationId\":\""+operation+"\",\"productId\":\""+productId
                +"\",\"type\":\"ENTRY\",\"direction\":\"INCREASE\",\"quantity\":3,\"reason\":\"entrada\"}";
        for (int i = 0; i < 2; i++) mvc.perform(post("/api/stock/movements").with(user("seller-audit").roles("SELLER"))
                .with(csrf()).contentType(MediaType.APPLICATION_JSON).content(movement)).andExpect(status().isCreated());
        assertThat(count(operation, "STOCK_MOVEMENT_CREATED")).isEqualTo(1);
        String saleId = UUID.randomUUID().toString();
        String sale = "{\"id\":\""+saleId+"\",\"customer\":{\"name\":\"Cliente privado\",\"phone\":\"" + next() + "\"},\"items\":[{\"productId\":\""
                +productId+"\",\"quantity\":1,\"expectedUnitPrice\":2}],\"deliverNow\":false,\"paid\":false}";
        for (int i = 0; i < 2; i++) mvc.perform(post("/api/sales").with(user("seller-audit").roles("SELLER"))
                .with(csrf()).contentType(MediaType.APPLICATION_JSON).content(sale)).andExpect(status().isCreated());
        assertThat(count(saleId, "SALE_CREATED")).isEqualTo(1);
        mvc.perform(patch("/api/sales/"+saleId+"/deliver").with(user("seller-audit").roles("SELLER")).with(csrf())).andExpect(status().isOk());
        mvc.perform(patch("/api/sales/"+saleId+"/pay").with(user("seller-audit").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"method\":\"CASH\"}")).andExpect(status().isOk());
        mvc.perform(patch("/api/sales/"+saleId+"/pay").with(user("seller-audit").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"method\":\"CASH\"}")).andExpect(status().isConflict());
        assertThat(count(saleId, "SALE_DELIVERED")).isEqualTo(1);
        assertThat(count(saleId, "SALE_MARKED_PAID")).isEqualTo(1);

        String result = mvc.perform(get("/api/audit/events?size=100").with(user("admin-audit").roles("ADMIN")))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].occurredAt").exists())
                .andReturn().getResponse().getContentAsString();
        assertThat(result).contains("admin-audit", "seller-audit", saleId, "SALE_MARKED_PAID")
                .doesNotContain(password, "841234567", "Nome privado", "Cliente privado");
        mvc.perform(get("/api/audit/events").with(user("seller").roles("SELLER"))).andExpect(status().isForbidden());
        mvc.perform(get("/api/audit/events")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/audit/events?size=101").with(user("admin").roles("ADMIN"))).andExpect(status().isBadRequest());
        mvc.perform(post("/api/audit/events").with(user("admin").roles("ADMIN")).with(csrf())).andExpect(status().isForbidden());
    }

    @Test void auditFailureRollsBackBusinessTransaction() {
        String[] id = new String[1];
        assertThatThrownBy(() -> transactions.executeWithoutResult(status -> {
            Customer customer = new Customer("Rollback", next());
            id[0] = customer.getId();
            em.persist(customer);
            audit.record("x".repeat(151), "CUSTOMER_CREATED", "CUSTOMER", id[0], "origin=SALE");
            em.flush();
        })).isInstanceOf(RuntimeException.class);
        assertThat(jdbc.queryForObject("select count(*) from customers where id = ?", Integer.class, id[0])).isZero();
        assertThat(count(id[0], "CUSTOMER_CREATED")).isZero();
    }

    private int count(String target, String action) {
        return jdbc.queryForObject("select count(*) from audit_events where target_id = ? and action = ?", Integer.class, target, action);
    }
}
