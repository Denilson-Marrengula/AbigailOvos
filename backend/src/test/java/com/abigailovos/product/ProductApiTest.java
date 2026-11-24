package com.abigailovos.product;

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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
class ProductApiTest {
    @Autowired MockMvc mvc;
    @Autowired ProductRepository repository;

    @BeforeEach
    void clearProducts() { repository.deleteAll(); }

    @Test
    void anonymousUsersCannotReadProducts() throws Exception {
        mvc.perform(get("/api/products")).andExpect(status().isUnauthorized());
    }

    @Test
    @WithMockUser(roles = "ADMIN")
    void administratorCreatesAndReadsProduct() throws Exception {
        var response = mvc.perform(post("/api/products").with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Ovos\",\"unit\":\"bandeja\",\"price\":125.50}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").isNotEmpty())
                .andExpect(jsonPath("$.createdAt").isNotEmpty())
                .andReturn().getResponse();
        mvc.perform(get(response.getHeader("Location")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.name").value("Ovos"))
                .andExpect(jsonPath("$.price").value(125.50)).andExpect(jsonPath("$.priceText").value("125.50"));
    }

    @Test
    @WithMockUser(roles = "SELLER")
    void sellerCanReadAndCreateProducts() throws Exception {
        mvc.perform(get("/api/products")).andExpect(status().isOk());
        mvc.perform(post("/api/products").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ovos\",\"unit\":\"bandeja\",\"price\":\"125.50\"}"))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.priceText").value("125.50"));
    }

    @Test
    @WithMockUser(roles = "ADMIN")
    void rejectsInvalidProductsAndRequiresCsrf() throws Exception {
        mvc.perform(post("/api/products").with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"  \",\"unit\":\"bandeja\",\"price\":-1}"))
                .andExpect(status().isBadRequest());
        mvc.perform(post("/api/products").contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ovos\",\"unit\":\"bandeja\",\"price\":1}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void bothCanEditButOnlyAdminCanChangeVisibility() throws Exception {
        Product product = repository.saveAndFlush(new Product("Ovos", "bandeja", java.math.BigDecimal.ONE));
        String path = "/api/products/" + product.getId();
        String data = "{\"name\":\"Ovos grandes\",\"unit\":\"caixa\",\"price\":\"12.50\"}";
        mvc.perform(put(path).with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data))
                .andExpect(status().isOk()).andExpect(jsonPath("$.priceText").value("12.50"));
        mvc.perform(patch(path + "/status").with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content("{\"active\":false}")).andExpect(status().isForbidden());
        mvc.perform(put(path).with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data))
                .andExpect(status().isOk()).andExpect(jsonPath("$.name").value("Ovos grandes"));
        mvc.perform(patch(path + "/status").with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content("{\"active\":false}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.active").value(false));
        mvc.perform(get(path).with(user("seller").roles("SELLER"))).andExpect(status().isNotFound());
        mvc.perform(put(path).with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content(data))
                .andExpect(status().isNotFound());
        mvc.perform(get("/api/products").with(user("seller").roles("SELLER"))).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        mvc.perform(get(path).with(user("admin").roles("ADMIN"))).andExpect(status().isOk()).andExpect(jsonPath("$.active").value(false));
        mvc.perform(patch(path + "/status").with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content("{\"active\":true}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.active").value(true));
        mvc.perform(get(path).with(user("seller").roles("SELLER"))).andExpect(status().isOk());
        mvc.perform(put(path).with(user("admin").roles("ADMIN")).with(csrf()).contentType(MediaType.APPLICATION_JSON).content("{\"name\":\" \",\"unit\":\"x\",\"price\":-1}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void minimumStockIsOptionalValidatedAndDoesNotChangeProductEdits() throws Exception {
        Product product = repository.saveAndFlush(new Product("Ovos", "bandeja", java.math.BigDecimal.ONE));
        String path = "/api/products/" + product.getId();
        mvc.perform(put(path + "/minimum-stock").with(user("seller").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"minimumStock\":\"3.50\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.minimumStockText").value("3.50"));
        mvc.perform(put(path).with(user("seller").roles("SELLER")).with(csrf()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Ovos novos\",\"unit\":\"bandeja\",\"price\":2}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.minimumStockText").value("3.50"));
        for (String value : new String[] {"-1", "1.234", "null"}) {
            mvc.perform(put(path + "/minimum-stock").with(user("seller").roles("SELLER")).with(csrf())
                    .contentType(MediaType.APPLICATION_JSON).content("{\"minimumStock\":" + value + "}"))
                    .andExpect(status().isBadRequest());
        }
        mvc.perform(delete(path + "/minimum-stock").with(user("admin").roles("ADMIN")).with(csrf()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.minimumStock").isEmpty());
        mvc.perform(put(path + "/minimum-stock").with(user("other").roles("OTHER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"minimumStock\":1}"))
                .andExpect(status().isForbidden());
    }
}
