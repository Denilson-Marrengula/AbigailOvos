package com.abigailovos.stock;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import com.fasterxml.jackson.databind.ObjectMapper;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest @AutoConfigureMockMvc
class StockApiTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;

    @Test @WithMockUser(username = "admin", roles = "ADMIN")
    void movementsArePersistedAndCannotOverdraw() throws Exception {
        String product = mvc.perform(post("/api/products").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ovos\",\"unit\":\"unidade\",\"price\":1}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String id = json.readTree(product).get("id").asText();
        String entry = "{\"operationId\":\"" + java.util.UUID.randomUUID() + "\",\"productId\":\"" + id + "\",\"type\":\"ENTRY\",\"direction\":\"INCREASE\",\"quantity\":10,\"reason\":\"Compra\"}";
        String loss = "{\"operationId\":\"" + java.util.UUID.randomUUID() + "\",\"productId\":\"" + id + "\",\"type\":\"LOSS\",\"direction\":\"DECREASE\",\"quantity\":11,\"reason\":\"Quebra\"}";
        mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(entry))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.administrator").value("seller"));
        mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(entry))
                .andExpect(status().isCreated());
        mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(entry.replace("\"quantity\":10", "\"quantity\":9")))
                .andExpect(status().isConflict());
        mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(loss))
                .andExpect(status().isBadRequest());
        mvc.perform(get("/api/stock/" + id)).andExpect(status().isOk()).andExpect(jsonPath("$.quantity").value(10));
        mvc.perform(get("/api/stock/" + id + "/movements")).andExpect(status().isOk())
                .andExpect(jsonPath("$[0].administrator").value("seller"))
                .andExpect(jsonPath("$[0].reason").value("Compra"))
                .andExpect(jsonPath("$[1]").doesNotExist());
        String adjustment = "{\"operationId\":\"" + java.util.UUID.randomUUID() + "\",\"productId\":\"" + id + "\",\"type\":\"ADJUSTMENT\",\"direction\":\"DECREASE\",\"quantity\":2,\"reason\":\"Contagem\"}";
        String breakage = "{\"operationId\":\"" + java.util.UUID.randomUUID() + "\",\"productId\":\"" + id + "\",\"type\":\"BREAKAGE\",\"direction\":\"DECREASE\",\"quantity\":1,\"reason\":\"Quebra\"}";
        String validLoss = "{\"operationId\":\"" + java.util.UUID.randomUUID() + "\",\"productId\":\"" + id + "\",\"type\":\"LOSS\",\"direction\":\"DECREASE\",\"quantity\":1,\"reason\":\"Perda\"}";
        for (String movement : new String[] { adjustment, breakage, validLoss }) {
            mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(movement))
                    .andExpect(status().isCreated());
        }
        mvc.perform(get("/api/stock/" + id)).andExpect(jsonPath("$.quantity").value(6));
        mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                        .content(entry.replace("ENTRY", "SALE"))).andExpect(status().isBadRequest());
    }

    @Test @WithMockUser(roles = "ADMIN")
    void administratorCannotCreateManualMovements() throws Exception {
        mvc.perform(post("/api/stock/movements").with(csrf()).contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isForbidden());
    }

    @Test @WithMockUser(roles = "SELLER")
    void sellerCannotViewAdministrativeHistory() throws Exception {
        mvc.perform(get("/api/stock/00000000-0000-0000-0000-000000000001/movements"))
                .andExpect(status().isForbidden());
    }

    @Test @WithMockUser(username = "admin", roles = "ADMIN")
    void inactiveProductRejectsNewMovementButAcceptsRetryOfExistingOne() throws Exception {
        String product = mvc.perform(post("/api/products").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ovos inativos\",\"unit\":\"unidade\",\"price\":1}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String id = json.readTree(product).get("id").asText();
        String operation = java.util.UUID.randomUUID().toString();
        String entry = "{\"operationId\":\""+operation+"\",\"productId\":\""+id+"\",\"type\":\"ENTRY\",\"direction\":\"INCREASE\",\"quantity\":1,\"reason\":\"Reposição\"}";
        mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(entry)).andExpect(status().isCreated());
        mvc.perform(patch("/api/products/"+id+"/status").with(csrf()).contentType(MediaType.APPLICATION_JSON).content("{\"active\":false}"))
                .andExpect(status().isOk());
        mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(entry)).andExpect(status().isCreated());
        mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content(entry.replace(operation, java.util.UUID.randomUUID().toString()))).andExpect(status().isNotFound());
        mvc.perform(get("/api/stock/"+id).with(user("seller").roles("SELLER"))).andExpect(status().isNotFound());
        mvc.perform(get("/api/stock/"+id)).andExpect(jsonPath("$.quantity").value(1));
    }

    @Test @WithMockUser(username = "admin", roles = "ADMIN")
    void simultaneousRetriesDoNotDuplicateMovement() throws Exception {
        String product = mvc.perform(post("/api/products").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ovos simultâneos\",\"unit\":\"unidade\",\"price\":1}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String id = json.readTree(product).get("id").asText();
        String entry = "{\"operationId\":\""+java.util.UUID.randomUUID()+"\",\"productId\":\""+id+"\",\"type\":\"ENTRY\",\"direction\":\"INCREASE\",\"quantity\":1,\"reason\":\"Reposição\"}";
        var start = new java.util.concurrent.CountDownLatch(1);
        try (var executor = java.util.concurrent.Executors.newFixedThreadPool(2)) {
            var first = executor.submit(() -> { start.await(); return mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(entry)).andReturn().getResponse().getStatus(); });
            var second = executor.submit(() -> { start.await(); return mvc.perform(post("/api/stock/movements").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(entry)).andReturn().getResponse().getStatus(); });
            start.countDown();
            org.assertj.core.api.Assertions.assertThat(first.get(15, java.util.concurrent.TimeUnit.SECONDS)).isEqualTo(201);
            org.assertj.core.api.Assertions.assertThat(second.get(15, java.util.concurrent.TimeUnit.SECONDS)).isEqualTo(201);
        }
        mvc.perform(get("/api/stock/"+id)).andExpect(jsonPath("$.quantity").value(1));
        mvc.perform(get("/api/stock/"+id+"/movements")).andExpect(jsonPath("$.length()").value(1));
    }
}
