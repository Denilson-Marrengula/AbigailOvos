package com.abigailovos.sales;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest @AutoConfigureMockMvc
class SalesApiTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;

    @Test void concurrentRetriesOfSameRequestDoNotDoubleReserve() throws Exception {
        String product = mvc.perform(post("/api/products").with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Concorrência\",\"unit\":\"unidade\",\"price\":2}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String productId = json.readTree(product).get("id").asText();
        mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"operationId\":\""+UUID.randomUUID()+"\",\"productId\":\""+productId+"\",\"type\":\"ENTRY\",\"direction\":\"INCREASE\",\"quantity\":1,\"reason\":\"entrada\"}"))
                .andExpect(status().isCreated());
        String id = UUID.randomUUID().toString();
        String request = "{\"id\":\""+id+"\",\"customer\":{\"name\":\"Mesmo cliente\"},\"items\":[{\"productId\":\""+productId+"\",\"quantity\":1,\"expectedUnitPrice\":2}],\"deliverNow\":false,\"paid\":false}";
        var start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(2)) {
            var first = executor.submit(() -> { start.await(); return mvc.perform(post("/api/sales").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(request)).andReturn().getResponse().getStatus(); });
            var second = executor.submit(() -> { start.await(); return mvc.perform(post("/api/sales").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(request)).andReturn().getResponse().getStatus(); });
            start.countDown();
            org.assertj.core.api.Assertions.assertThat(first.get(15, TimeUnit.SECONDS)).isEqualTo(201);
            org.assertj.core.api.Assertions.assertThat(second.get(15, TimeUnit.SECONDS)).isEqualTo(201);
        }
        mvc.perform(get("/api/stock/"+productId).with(user("seller").roles("SELLER")))
                .andExpect(jsonPath("$.quantity").value(1)).andExpect(jsonPath("$.reserved").value(1));
    }

    @Test void reservationsDeliveryPaymentAndCancellation() throws Exception {
        String product = mvc.perform(post("/api/products").with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ovos\",\"unit\":\"unidade\",\"price\":2}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String productId = json.readTree(product).get("id").asText();
        mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"operationId\":\""+UUID.randomUUID()+"\",\"productId\":\""+productId+"\",\"type\":\"ENTRY\",\"direction\":\"INCREASE\",\"quantity\":10,\"reason\":\"entrada\"}"))
                .andExpect(status().isCreated());
        String id = UUID.randomUUID().toString();
        String request = "{\"id\":\""+id+"\",\"customer\":{\"name\":\"Maria\"},\"items\":[{\"productId\":\""+productId+"\",\"quantity\":\"6\",\"expectedUnitPrice\":\"2.00\"}],\"deliverNow\":false,\"paid\":false}";
        mvc.perform(post("/api/sales").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.total").value(12)).andExpect(jsonPath("$.totalText").value("12.00")).andExpect(jsonPath("$.deliveryStatus").value("PENDING"));
        mvc.perform(post("/api/sales").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.id").value(id));
        mvc.perform(post("/api/sales").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(request.replace("Maria", "Outro")))
                .andExpect(status().isConflict());
        mvc.perform(get("/api/stock/"+productId).with(user("seller").roles("SELLER")))
                .andExpect(jsonPath("$.quantity").value(10)).andExpect(jsonPath("$.reserved").value(6)).andExpect(jsonPath("$.available").value(4));
        mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"operationId\":\""+UUID.randomUUID()+"\",\"productId\":\""+productId+"\",\"type\":\"LOSS\",\"direction\":\"DECREASE\",\"quantity\":5,\"reason\":\"perda\"}"))
                .andExpect(status().isBadRequest());
        String tooMany = "{\"id\":\""+UUID.randomUUID()+"\",\"customer\":{\"name\":\"NaoCriar\"},\"items\":[{\"productId\":\""+productId+"\",\"quantity\":5,\"expectedUnitPrice\":2}],\"deliverNow\":true,\"paid\":false}";
        mvc.perform(post("/api/sales").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(tooMany)).andExpect(status().isConflict());
        mvc.perform(get("/api/customers").with(user("seller").roles("SELLER"))).andExpect(jsonPath("$[?(@.name == 'NaoCriar')]").isEmpty());
        mvc.perform(patch("/api/sales/"+id+"/deliver").with(user("seller").roles("SELLER")).with(csrf())).andExpect(status().isOk());
        mvc.perform(patch("/api/sales/"+id+"/deliver").with(user("seller").roles("SELLER")).with(csrf())).andExpect(status().isConflict());
        mvc.perform(get("/api/stock/"+productId).with(user("seller").roles("SELLER")))
                .andExpect(jsonPath("$.quantity").value(4)).andExpect(jsonPath("$.reserved").value(0));
        mvc.perform(patch("/api/sales/"+id+"/pay").with(user("seller").roles("SELLER")).with(csrf())).andExpect(status().isOk()).andExpect(jsonPath("$.paymentStatus").value("PAID"));
        mvc.perform(patch("/api/sales/"+id+"/cancel").with(user("seller").roles("SELLER")).with(csrf())).andExpect(status().isConflict());
        String cancelId = UUID.randomUUID().toString();
        String pending = request.replace(id, cancelId).replace("\"quantity\":\"6\"", "\"quantity\":\"2\"");
        mvc.perform(post("/api/sales").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(pending)).andExpect(status().isCreated());
        mvc.perform(patch("/api/sales/"+cancelId+"/cancel").with(user("seller").roles("SELLER")).with(csrf())).andExpect(status().isOk()).andExpect(jsonPath("$.deliveryStatus").value("CANCELLED"));
        mvc.perform(get("/api/stock/"+productId).with(user("seller").roles("SELLER"))).andExpect(jsonPath("$.quantity").value(4)).andExpect(jsonPath("$.available").value(4));
        String immediate = pending.replace(cancelId, UUID.randomUUID().toString()).replace("\"deliverNow\":false", "\"deliverNow\":true");
        mvc.perform(post("/api/sales").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(immediate)).andExpect(status().isCreated()).andExpect(jsonPath("$.deliveryStatus").value("DELIVERED"));
        mvc.perform(get("/api/stock/"+productId).with(user("seller").roles("SELLER"))).andExpect(jsonPath("$.quantity").value(2)).andExpect(jsonPath("$.reserved").value(0));
        String stalePrice = immediate.replace("\"expectedUnitPrice\":\"2.00\"", "\"expectedUnitPrice\":\"1.00\"").replace("\"name\":\"Maria\"", "\"name\":\"PrecoAlterado\"").replaceAll("\\\"id\\\":\\\"[^\\\"]+\\\"", "\"id\":\""+UUID.randomUUID()+"\"");
        mvc.perform(post("/api/sales").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(stalePrice)).andExpect(status().isConflict());
        mvc.perform(get("/api/customers").with(user("seller").roles("SELLER"))).andExpect(jsonPath("$[?(@.name == 'PrecoAlterado')]").isEmpty());
        mvc.perform(post("/api/sales").with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(request)).andExpect(status().isForbidden());
    }
}
