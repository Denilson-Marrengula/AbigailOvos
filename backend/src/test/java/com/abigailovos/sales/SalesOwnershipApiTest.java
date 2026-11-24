package com.abigailovos.sales;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import static org.assertj.core.api.Assertions.assertThat;
import static com.abigailovos.testutil.TestPhones.next;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Uses a case-insensitive database deliberately, so the Java identity check matters. */
@SpringBootTest(properties = "spring.datasource.url=jdbc:h2:mem:sales_scope;MODE=MySQL;IGNORECASE=TRUE;DB_CLOSE_DELAY=-1")
@AutoConfigureMockMvc
class SalesOwnershipApiTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;

    @Test void isolatesSellersAndAuditsAdministrativeAssistance() throws Exception {
        String product = mvc.perform(post("/api/products").with(user("admin").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Produto\",\"unit\":\"unidade\",\"price\":2}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String productId = json.readTree(product).get("id").asText();
        mvc.perform(post("/api/stock/movements").with(user("ana").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"operationId\":\"" + UUID.randomUUID()
                        + "\",\"productId\":\"" + productId + "\",\"type\":\"ENTRY\",\"direction\":\"INCREASE\",\"quantity\":5,\"reason\":\"entrada\"}"))
                .andExpect(status().isCreated());

        String ana = UUID.randomUUID().toString();
        String historicalCase = UUID.randomUUID().toString();
        String bia = UUID.randomUUID().toString();
        String cancellable = UUID.randomUUID().toString();
        String anaRequest = createSale(ana, "ana", productId);
        // Authentication mocks emulate a historical case collision; normal account creation reserves names.
        createSale(historicalCase, "Ana", productId);
        createSale(bia, "bia", productId);
        createSale(cancellable, "ana", productId);

        assertThat(jdbc.queryForObject("select count(*) from sales where seller = ?", Integer.class, "ana")).isEqualTo(3);
        assertThat(idsFor("ana", "SELLER")).containsExactlyInAnyOrder(ana, cancellable);
        assertThat(idsFor("Ana", "SELLER")).containsExactly(historicalCase);
        assertThat(idsFor("bia", "SELLER")).containsExactly(bia);
        assertThat(idsFor("admin", "ADMIN")).containsExactlyInAnyOrder(ana, historicalCase, bia, cancellable);
        var firstPage = json.readTree(mvc.perform(get("/api/sales/search").param("size", "1")
                .with(user("ana").roles("SELLER"))).andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1)).andExpect(jsonPath("$.hasMore").value(true))
                .andReturn().getResponse().getContentAsString());
        var secondPage = json.readTree(mvc.perform(get("/api/sales/search").param("size", "1").param("page", "1")
                .with(user("ana").roles("SELLER"))).andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1)).andExpect(jsonPath("$.hasMore").value(false))
                .andReturn().getResponse().getContentAsString());
        assertThat(Set.of(firstPage.get("items").get(0).get("id").asText(),
                secondPage.get("items").get(0).get("id").asText())).containsExactlyInAnyOrder(ana, cancellable);
        mvc.perform(get("/api/sales/search").param("seller", "Ana").with(user("ana").roles("SELLER")))
                .andExpect(status().isForbidden());
        mvc.perform(get("/api/sales/search").param("customer", "Cliente ana").param("product", "Produto")
                .with(user("ana").roles("SELLER"))).andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(2));
        mvc.perform(get("/api/sales")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/sales").with(user("outro").roles("OTHER"))).andExpect(status().isForbidden());
        mvc.perform(get("/api/customers").with(user("bia").roles("SELLER")))
                .andExpect(status().isOk()).andExpect(jsonPath("$[?(@.name == 'Cliente ana')]").isNotEmpty());

        mvc.perform(post("/api/sales").with(user("bia").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(anaRequest)).andExpect(status().isConflict());
        mvc.perform(post("/api/sales").with(user("ana").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(anaRequest)).andExpect(status().isCreated());
        mvc.perform(post("/api/sales").with(user("admin").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(anaRequest)).andExpect(status().isForbidden());

        for (String stranger : new String[] {"bia", "Ana"}) {
            mvc.perform(patch("/api/sales/" + ana + "/deliver").with(user(stranger).roles("SELLER")).with(csrf()))
                    .andExpect(status().isNotFound());
            mvc.perform(patch("/api/sales/" + ana + "/cancel").with(user(stranger).roles("SELLER")).with(csrf()))
                    .andExpect(status().isNotFound());
            mvc.perform(patch("/api/sales/" + ana + "/pay").with(user(stranger).roles("SELLER")).with(csrf())
                    .contentType(MediaType.APPLICATION_JSON).content("{\"method\":\"CASH\"}"))
                    .andExpect(status().isNotFound());
        }
        mvc.perform(patch("/api/sales/" + ana + "/cancel").with(user("admin").roles("ADMIN")).with(csrf()))
                .andExpect(status().isForbidden());
        mvc.perform(patch("/api/sales/" + ana + "/deliver").with(user("admin").roles("ADMIN")))
                .andExpect(status().isForbidden());
        mvc.perform(patch("/api/sales/" + ana + "/pay").with(user("admin").roles("ADMIN"))
                .contentType(MediaType.APPLICATION_JSON).content("{\"method\":\"CASH\"}"))
                .andExpect(status().isForbidden());
        mvc.perform(patch("/api/sales/" + ana + "/deliver").with(user("ana").roles("SELLER")))
                .andExpect(status().isForbidden());
        assertThat(jdbc.queryForObject("select count(*) from audit_events where target_id = ? and action in ('SALE_DELIVERED', 'SALE_MARKED_PAID', 'SALE_CANCELLED')", Integer.class, ana)).isZero();
        mvc.perform(get("/api/stock/" + productId).with(user("bia").roles("SELLER")))
                .andExpect(jsonPath("$.quantity").value(5)).andExpect(jsonPath("$.reserved").value(4));

        mvc.perform(patch("/api/sales/" + ana + "/deliver").with(user("admin").roles("ADMIN")).with(csrf()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.seller").value("ana"))
                .andExpect(jsonPath("$.deliveryStatus").value("DELIVERED"));
        assertThat(jdbc.queryForObject("select updated_by from sales where id = ?", String.class, ana)).isEqualTo("admin");
        assertThat(jdbc.queryForObject("select delivered_at from sales where id = ?", java.sql.Timestamp.class, ana)).isNotNull();
        assertThat(jdbc.queryForObject("select administrator from stock_movements where reason = ?", String.class, "Venda " + ana)).isEqualTo("admin");
        mvc.perform(patch("/api/sales/" + ana + "/pay").with(user("admin2").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"method\":\"MPESA\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.seller").value("ana"))
                .andExpect(jsonPath("$.paymentStatus").value("PAID")).andExpect(jsonPath("$.paymentMethod").value("MPESA"));
        assertThat(jdbc.queryForObject("select seller from sales where id = ?", String.class, ana)).isEqualTo("ana");
        assertThat(jdbc.queryForObject("select updated_by from sales where id = ?", String.class, ana)).isEqualTo("admin2");
        assertThat(jdbc.queryForObject("select paid_at from sales where id = ?", java.sql.Timestamp.class, ana)).isNotNull();
        assertActor(ana, "SALE_DELIVERED", "admin");
        assertActor(ana, "SALE_MARKED_PAID", "admin2");
        mvc.perform(patch("/api/sales/" + ana + "/pay").with(user("admin2").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"method\":\"MPESA\"}")).andExpect(status().isConflict());
        assertThat(jdbc.queryForObject("select count(*) from audit_events where target_id = ? and action = 'SALE_MARKED_PAID'", Integer.class, ana)).isEqualTo(1);

        mvc.perform(patch("/api/sales/" + cancellable + "/cancel").with(user("ana").roles("SELLER")).with(csrf()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.deliveryStatus").value("CANCELLED"));
        assertThat(jdbc.queryForObject("select cancelled_at from sales where id = ?", java.sql.Timestamp.class, cancellable)).isNotNull();
        mvc.perform(get("/api/stock/" + productId).with(user("bia").roles("SELLER")))
                .andExpect(jsonPath("$.quantity").value(4)).andExpect(jsonPath("$.reserved").value(2))
                .andExpect(jsonPath("$.available").value(2));
    }

    private String createSale(String id, String seller, String productId) throws Exception {
        String request = "{\"id\":\"" + id + "\",\"customer\":{\"name\":\"Cliente " + seller
                + "\",\"phone\":\"" + next() + "\"},\"items\":[{\"productId\":\"" + productId
                + "\",\"quantity\":1,\"expectedUnitPrice\":2}],\"deliverNow\":false,\"paid\":false}";
        mvc.perform(post("/api/sales").with(user(seller).roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(request)).andExpect(status().isCreated());
        return request;
    }

    private Set<String> idsFor(String username, String role) throws Exception {
        String response = mvc.perform(get("/api/sales").with(user(username).roles(role))).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        Set<String> ids = new HashSet<>();
        for (JsonNode sale : json.readTree(response)) ids.add(sale.get("id").asText());
        return ids;
    }

    private void assertActor(String id, String action, String actor) {
        assertThat(jdbc.queryForObject("select actor from audit_events where target_id = ? and action = ?", String.class, id, action)).isEqualTo(actor);
    }
}
