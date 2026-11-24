package com.abigailovos.sales;

import java.net.URI;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import static org.assertj.core.api.Assertions.assertThat;
import static com.abigailovos.testutil.TestPhones.next;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Optional destructive-to-the-test-schema integration tests. Never use a real
 * instance or data. The schema must already exist and be empty; nothing is
 * dropped automatically. The opt-in and connection checks run before Flyway.
 */
@EnabledIfEnvironmentVariable(named = "ABIGAIL_TIDB_TEST_CONFIRM", matches = "ISOLATED_FAKE_DATA_ONLY")
@SpringBootTest
@AutoConfigureMockMvc
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
class IsolatedTidbCompatibilityTest extends ActivityReportStorageContract {
    // Despite its name, this schema was selected by the owner for real operations.
    private static final String RESERVED_OPERATIONAL_SCHEMA = "abigailovos_tidb_test_4292b79106cb4fac";

    record Target(String url, String username, String password, String schema) {
        @Override
        public String toString() {
            return "Target[redacted]";
        }
    }

    @DynamicPropertySource
    static void isolatedDatabase(DynamicPropertyRegistry properties) {
        Target target = validatedTarget();
        requireEmptyIsolatedSchema(target);
        properties.add("spring.datasource.url", target::url);
        properties.add("spring.datasource.username", target::username);
        properties.add("spring.datasource.password", target::password);
        properties.add("spring.datasource.driver-class-name", () -> "com.mysql.cj.jdbc.Driver");
        properties.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
        properties.add("spring.flyway.enabled", () -> "true");
        properties.add("abigail.bootstrap.enabled", () -> "false");
    }

    private static Target validatedTarget() {
        return validatedTarget(System.getenv("ABIGAIL_TIDB_TEST_URL"),
                System.getenv("ABIGAIL_TIDB_TEST_USER"), System.getenv("ABIGAIL_TIDB_TEST_PASSWORD"));
    }

    static Target validatedTarget(String url, String username, String password) {
        if (url == null || username == null || username.isBlank() || password == null || password.isBlank()
                || isRootAccount(username) || !url.startsWith("jdbc:mysql://")) {
            throw new IllegalStateException("Configure uma ligação TiDB isolada com uma conta de teste; a conta root é recusada.");
        }
        URI uri;
        try {
            uri = URI.create(url.substring("jdbc:".length()));
        } catch (IllegalArgumentException ex) {
            throw new IllegalStateException("Endereço de teste inválido; não inclua credenciais na URL.");
        }
        String host = uri.getHost();
        String path = uri.getRawPath();
        if (host == null || !host.toLowerCase(Locale.ROOT).endsWith(".tidbcloud.com")
                || uri.getPort() < 1 || uri.getPort() > 65535 || uri.getRawUserInfo() != null
                || uri.getRawFragment() != null || path == null
                || !path.matches("/abigailovos_tidb_test_[a-z0-9]{8,32}")
                || ("/" + RESERVED_OPERATIONAL_SCHEMA).equalsIgnoreCase(path)
                || !"sslMode=VERIFY_IDENTITY".equals(uri.getRawQuery())) {
            throw new IllegalStateException("Ligação recusada: use a base de teste dedicada e TLS com verificação de identidade.");
        }
        return new Target(url, username, password, path.substring(1));
    }

    // A name check cannot verify whether another account has broad privileges.
    private static boolean isRootAccount(String username) {
        String normalized = username.strip().toLowerCase(Locale.ROOT);
        return "root".equals(normalized) || normalized.endsWith(".root");
    }

    private static void requireEmptyIsolatedSchema(Target target) {
        try (Connection connection = DriverManager.getConnection(target.url(), target.username(), target.password());
                var statement = connection.createStatement()) {
            try (ResultSet result = statement.executeQuery("SELECT DATABASE(), @@tidb_txn_mode, @@foreign_key_checks")) {
                if (!result.next() || !target.schema().equals(result.getString(1))
                        || !"pessimistic".equalsIgnoreCase(result.getString(2)) || result.getInt(3) != 1) {
                    throw new IllegalStateException("Base de teste ou configuração de transações/relações inesperada.");
                }
            }
            try (ResultSet result = statement.executeQuery(
                    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()")) {
                if (!result.next() || result.getLong(1) != 0) {
                    throw new IllegalStateException("A base de teste tem de estar vazia; nada será apagado.");
                }
            }
        } catch (SQLException ex) {
            // Avoid logging credentials or connection details supplied by the operator.
            throw new IllegalStateException("Não foi possível verificar a base isolada de teste.");
        }
    }

    @Test
    void simultaneousOrdersCannotReserveMoreThanAvailable() throws Exception {
        String product = productWithOneUnit();
        UUID first = UUID.randomUUID();
        UUID second = UUID.randomUUID();
        List<Integer> results = sendTogether(request(first, product), request(second, product));
        assertThat(results).containsExactlyInAnyOrder(201, 409);
        assertBalance(product, 1, 1, 0);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM sales WHERE id IN (?, ?)", Integer.class,
                first.toString(), second.toString())).isEqualTo(1);
    }

    @Test
    void concurrentRetryWithSameOperationIdDoesNotDuplicateTheReservation() throws Exception {
        String product = productWithOneUnit();
        UUID id = UUID.randomUUID();
        String request = request(id, product);
        assertThat(sendTogether(request, request)).containsExactlyInAnyOrder(201, 201);
        assertBalance(product, 1, 1, 0);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM sales WHERE id = ?", Integer.class,
                id.toString())).isEqualTo(1);
    }

    @Test
    void customerForeignKeyRejectsOrphanSale() {
        String id = UUID.randomUUID().toString();
        String missingCustomer = UUID.randomUUID().toString();
        assertThatThrownBy(() -> jdbc.update(
                "INSERT INTO sales (id, request_hash, customer_id, seller, delivery_status, payment_status, total, created_at, updated_at, updated_by) "
                + "VALUES (?, ?, ?, ?, 'PENDING', 'PENDING', 1, CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), ?)",
                id, "a".repeat(64), missingCustomer, "vendedor_teste", "vendedor_teste"))
                .isInstanceOf(DataIntegrityViolationException.class);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM sales WHERE id = ?", Integer.class, id)).isZero();
    }

    @Test
    void sellerIsolationAndAdminAssistancePreserveOwnerAndAudit() throws Exception {
        String product = productWithOneUnit();
        UUID id = UUID.randomUUID();
        assertThat(submit(request(id, product))).isEqualTo(201);
        String path = "/api/sales/" + id;
        mvc.perform(get("/api/sales").with(user("vendedor_teste").roles("SELLER")))
                .andExpect(status().isOk()).andExpect(jsonPath("$[?(@.id == '" + id + "')]").isNotEmpty());
        mvc.perform(get("/api/sales").with(user("outro_teste").roles("SELLER")))
                .andExpect(status().isOk()).andExpect(jsonPath("$[?(@.id == '" + id + "')]").isEmpty());
        mvc.perform(patch(path + "/deliver").with(user("outro_teste").roles("SELLER")).with(csrf()))
                .andExpect(status().isNotFound());
        mvc.perform(patch(path + "/cancel").with(user("admin_teste").roles("ADMIN")).with(csrf()))
                .andExpect(status().isForbidden());
        mvc.perform(patch(path + "/deliver").with(user("admin_teste").roles("ADMIN")).with(csrf()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.seller").value("vendedor_teste"));
        mvc.perform(patch(path + "/pay").with(user("admin_teste").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content("{\"method\":\"CASH\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.seller").value("vendedor_teste"));
        assertThat(jdbc.queryForObject("SELECT seller FROM sales WHERE id = ?", String.class, id.toString()))
                .isEqualTo("vendedor_teste");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM audit_events WHERE target_id = ? AND actor = ? AND action IN ('SALE_DELIVERED', 'SALE_MARKED_PAID')",
                Integer.class, id.toString(), "admin_teste")).isEqualTo(2);
        assertBalance(product, 0, 0, 0);
    }

    @Test
    void concurrentCustomersWithSameNormalizedPhoneDoNotDuplicate() throws Exception {
        String firstProduct = productWithOneUnit();
        String secondProduct = productWithOneUnit();
        String phone = next();
        UUID first = UUID.randomUUID();
        UUID second = UUID.randomUUID();
        assertThat(sendTogether(request(first, firstProduct, phone), request(second, secondProduct, "+258 " + phone)))
                .containsExactlyInAnyOrder(201, 409);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM customers WHERE phone_key = ?", Integer.class, "+258" + phone)).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM sales WHERE id IN (?, ?)", Integer.class,
                first.toString(), second.toString())).isEqualTo(1);
    }

    private String productWithOneUnit() throws Exception {
        String payload = json.writeValueAsString(Map.of("name", "Produto fictício " + UUID.randomUUID(),
                "unit", "unidade", "price", 2));
        String response = mvc.perform(post("/api/products").with(user("admin_teste").roles("ADMIN")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(payload))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String product = json.readTree(response).get("id").asText();
        String movement = json.writeValueAsString(Map.of("operationId", UUID.randomUUID().toString(),
                "productId", product, "type", "ENTRY", "direction", "INCREASE", "quantity", 1,
                "reason", "Entrada fictícia"));
        mvc.perform(post("/api/stock/movements").with(user("vendedor_teste").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(movement)).andExpect(status().isCreated());
        return product;
    }

    private String request(UUID id, String product) throws Exception {
        return request(id, product, next());
    }

    private String request(UUID id, String product, String phone) throws Exception {
        return json.writeValueAsString(Map.of("id", id.toString(), "customer", Map.of("name", "Cliente fictício " + id, "phone", phone),
                "items", List.of(Map.of("productId", product, "quantity", 1, "expectedUnitPrice", 2)),
                "deliverNow", false, "paid", false));
    }

    private List<Integer> sendTogether(String first, String second) throws Exception {
        var start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(2)) {
            var a = executor.submit(() -> {
                start.await();
                return submit(first);
            });
            var b = executor.submit(() -> {
                start.await();
                return submit(second);
            });
            start.countDown();
            return List.of(a.get(60, TimeUnit.SECONDS), b.get(60, TimeUnit.SECONDS));
        }
    }

    private int submit(String request) throws Exception {
        return mvc.perform(post("/api/sales").with(user("vendedor_teste").roles("SELLER")).with(csrf())
                .contentType(MediaType.APPLICATION_JSON).content(request)).andReturn().getResponse().getStatus();
    }

    private void assertBalance(String product, int physical, int reserved, int available) throws Exception {
        mvc.perform(get("/api/stock/" + product).with(user("vendedor_teste").roles("SELLER")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.quantity").value(physical))
                .andExpect(jsonPath("$.reserved").value(reserved)).andExpect(jsonPath("$.available").value(available));
    }
}
