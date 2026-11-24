package com.abigailovos.sales;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.StreamSupport;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import static com.abigailovos.testutil.TestPhones.next;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Shared contract: H2 locally and TiDB only under the isolated test opt-in. */
abstract class ActivityReportStorageContract {
    @Autowired protected MockMvc mvc;
    @Autowired protected ObjectMapper json;
    @Autowired protected JdbcTemplate jdbc;

    @Test void reportsSeparatePeriodEventsFromCurrentDebtsAndOrders() throws Exception {
        UUID paidSale = UUID.randomUUID();
        UUID debtSale = UUID.randomUUID();
        UUID paidOrder = UUID.randomUUID();
        String paidCustomer = contractSale(paidSale, true, true, "MPESA");
        String debtCustomer = contractSale(debtSale, true, false, null);
        contractSale(paidOrder, false, true, "CASH");

        jdbc.update("UPDATE sales SET delivered_at=?, paid_at=? WHERE id=?",
                timestamp("2099-01-09T22:00:00Z"), timestamp("2099-01-10T21:59:59Z"), paidSale.toString());
        jdbc.update("UPDATE sales SET delivered_at=? WHERE id=?",
                timestamp("2099-01-09T21:59:59Z"), debtSale.toString());
        jdbc.update("UPDATE sales SET paid_at=? WHERE id=?",
                timestamp("2099-01-04T10:00:00Z"), paidOrder.toString());

        String body = mvc.perform(get("/api/reports/activity").param("from", "2099-01-10").param("to", "2099-01-10")
                .with(user("admin_teste").roles("ADMIN")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.timeZone").value("Africa/Maputo"))
                .andExpect(jsonPath("$.deliveredAmount").value("2.00"))
                .andExpect(jsonPath("$.paidAmount").value("2.00"))
                .andExpect(jsonPath("$.deliveredCustomers.length()").value(1))
                .andExpect(jsonPath("$.deliveredCustomers[0].customerId").value(paidCustomer))
                .andExpect(jsonPath("$.deliveries.length()").value(1))
                .andExpect(jsonPath("$.deliveries[0].id").value(paidSale.toString()))
                .andExpect(jsonPath("$.deliveries[0].seller").value("vendedor_teste"))
                .andExpect(jsonPath("$.deliveries[0].items[0].lineTotal").value("2.00"))
                .andExpect(jsonPath("$.paymentMethods[1].method").value("MPESA"))
                .andExpect(jsonPath("$.paymentMethods[1].amount").value("2.00"))
                .andReturn().getResponse().getContentAsString();
        JsonNode report = json.readTree(body);
        JsonNode debt = row(report.path("debtCustomers"), "customerId", debtCustomer);
        assertThat(debt.path("amount").asText()).isEqualTo("2.00");
        JsonNode order = row(report.path("pendingOrders"), "id", paidOrder.toString());
        assertThat(order.path("paymentStatus").asText()).isEqualTo("PAID");
        assertThat(order.path("paymentMethod").asText()).isEqualTo("CASH");

        mvc.perform(get("/api/reports/sales").param("from", "2099-01-10").param("to", "2099-01-10")
                .with(user("admin_teste").roles("ADMIN")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.deliveredSales").value(1))
                .andExpect(jsonPath("$.deliveredAmount").value("2.00"))
                .andExpect(jsonPath("$.markedPaid").value(1))
                .andExpect(jsonPath("$.markedPaidAmount").value("2.00"));
        mvc.perform(get("/api/reports/activity").param("from", "2099-01-10").param("to", "2099-01-10")
                .with(user("vendedor_teste").roles("SELLER"))).andExpect(status().isForbidden());
    }

    private String contractSale(UUID id, boolean delivered, boolean paid, String method) throws Exception {
        String product = contractProductWithOneUnit();
        Map<String, Object> request = new LinkedHashMap<>();
        request.put("id", id.toString());
        request.put("customer", Map.of("name", "Cliente ficticio " + id, "phone", next()));
        request.put("items", List.of(Map.of("productId", product, "quantity", 1, "expectedUnitPrice", 2)));
        request.put("deliverNow", delivered);
        request.put("paid", paid);
        if (method != null) request.put("paymentMethod", method);
        String response = mvc.perform(post("/api/sales").with(user("vendedor_teste").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(request)))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        return json.readTree(response).path("customerId").asText();
    }

    private String contractProductWithOneUnit() throws Exception {
        String payload = json.writeValueAsString(Map.of("name", "Produto ficticio " + UUID.randomUUID(),
                "unit", "unidade", "price", 2));
        String response = mvc.perform(post("/api/products").with(user("admin_teste").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(payload))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String product = json.readTree(response).path("id").asText();
        String movement = json.writeValueAsString(Map.of("operationId", UUID.randomUUID().toString(),
                "productId", product, "type", "ENTRY", "direction", "INCREASE", "quantity", 1,
                "reason", "Entrada ficticia"));
        mvc.perform(post("/api/stock/movements").with(user("vendedor_teste").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(movement)).andExpect(status().isCreated());
        return product;
    }

    private JsonNode row(JsonNode array, String field, String id) {
        assertThat(array.isArray()).isTrue();
        return StreamSupport.stream(array.spliterator(), false)
                .filter(entry -> id.equals(entry.path(field).asText()))
                .findFirst().orElseThrow(() -> new AssertionError("Registo de teste ausente do relatório"));
    }

    private Timestamp timestamp(String value) { return Timestamp.from(Instant.parse(value)); }
}
