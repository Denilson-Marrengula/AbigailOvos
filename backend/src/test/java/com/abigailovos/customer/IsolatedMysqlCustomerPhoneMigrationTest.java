package com.abigailovos.customer;

import java.sql.DriverManager;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import static org.assertj.core.api.Assertions.*;

/** Only use new, empty local MySQL schemas with synthetic data. Never drops anything. */
@EnabledIfEnvironmentVariable(named = "ABIGAIL_MYSQL_V9_PORT", matches = "[0-9]+")
class IsolatedMysqlCustomerPhoneMigrationTest {
    private String url(String schema) {
        return "jdbc:mysql://127.0.0.1:" + System.getenv("ABIGAIL_MYSQL_V9_PORT") + "/" + schema;
    }

    private Flyway flyway(String schema, String target) {
        return Flyway.configure().dataSource(url(schema), "root", "").locations("classpath:db/migration").target(target).load();
    }

    @Test void validLegacyNumbersAndSaleHistoryArePreserved() throws Exception {
        String schema = "abigailovos_v12_isolated_ok";
        assertThat(flyway(schema, "11").migrate().migrationsExecuted).isEqualTo(11);
        try (var connection = DriverManager.getConnection(url(schema), "root", ""); var sql = connection.createStatement()) {
            sql.executeUpdate("insert into customers (id,name,phone,created_at,updated_at) values ('c1','Cliente teste','84 123 4567',now(6),now(6))");
            sql.executeUpdate("insert into sales (id,request_hash,customer_id,seller,delivery_status,payment_status,total,created_at,updated_at,updated_by) values ('s1','hash','c1','ana','PENDING','PENDING',12.50,now(6),now(6),'ana')");
        }
        assertThat(flyway(schema, "12").migrate().migrationsExecuted).isEqualTo(1);
        assertThat(flyway(schema, "12").migrate().migrationsExecuted).isZero();
        try (var connection = DriverManager.getConnection(url(schema), "root", ""); var sql = connection.createStatement()) {
            try (var rows = sql.executeQuery("select phone, phone_key from customers where id='c1'")) {
                assertThat(rows.next()).isTrue();
                assertThat(rows.getString(1)).isEqualTo("84 123 4567");
                assertThat(rows.getString(2)).isEqualTo("+258841234567");
            }
            try (var rows = sql.executeQuery("select customer_id, total from sales where id='s1'")) {
                assertThat(rows.next()).isTrue();
                assertThat(rows.getString(1)).isEqualTo("c1");
                assertThat(rows.getBigDecimal(2)).isEqualByComparingTo("12.50");
            }
            assertThatThrownBy(() -> sql.executeUpdate("insert into customers (id,name,phone,phone_key,created_at,updated_at) values ('c2','Outro','+258841234567','+258841234567',now(6),now(6))"))
                    .isInstanceOf(java.sql.SQLException.class);
        }
    }

    @Test void missingOrInvalidPhoneStopsBeforeChangingCustomerTable() throws Exception {
        String schema = "abigailovos_v12_isolated_invalid";
        flyway(schema, "11").migrate();
        try (var connection = DriverManager.getConnection(url(schema), "root", ""); var sql = connection.createStatement()) {
            sql.executeUpdate("insert into customers (id,name,phone,created_at,updated_at) values ('c1','Sem telefone',null,now(6),now(6)),('c2','Inválido','123',now(6),now(6))");
        }
        assertThatThrownBy(() -> flyway(schema, "12").migrate()).isInstanceOf(RuntimeException.class);
        assertUnchanged(schema, 2);
    }

    @Test void equivalentPhonesStopBeforeChangingCustomerTable() throws Exception {
        String schema = "abigailovos_v12_isolated_duplicate";
        flyway(schema, "11").migrate();
        try (var connection = DriverManager.getConnection(url(schema), "root", ""); var sql = connection.createStatement()) {
            sql.executeUpdate("insert into customers (id,name,phone,created_at,updated_at) values ('c1','A','84 123 4567',now(6),now(6)),('c2','B','+258841234567',now(6),now(6))");
        }
        assertThatThrownBy(() -> flyway(schema, "12").migrate()).isInstanceOf(RuntimeException.class);
        assertUnchanged(schema, 2);
    }

    private void assertUnchanged(String schema, int expected) throws Exception {
        try (var connection = DriverManager.getConnection(url(schema), "root", ""); var sql = connection.createStatement()) {
            try (var rows = sql.executeQuery("select count(*) from customers")) {
                assertThat(rows.next()).isTrue();
                assertThat(rows.getInt(1)).isEqualTo(expected);
            }
            try (var rows = sql.executeQuery("select count(*) from information_schema.columns where table_schema=database() and table_name='customers' and column_name='phone_key'")) {
                assertThat(rows.next()).isTrue();
                assertThat(rows.getInt(1)).isZero();
            }
        }
    }
}
