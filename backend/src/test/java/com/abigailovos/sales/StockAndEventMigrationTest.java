package com.abigailovos.sales;

import java.sql.DriverManager;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

/** Isolated H2 migration check; it does not connect to or modify an existing database. */
class StockAndEventMigrationTest {
    @Test void v17PreservesExistingRowsAndLeavesEventDatesUnknown() throws Exception {
        String url = "jdbc:h2:mem:v17_preservation;MODE=MySQL;DB_CLOSE_DELAY=-1";
        try (var connection = DriverManager.getConnection(url, "sa", ""); var sql = connection.createStatement()) {
            sql.execute("create table products (id varchar(36) primary key, name varchar(150) not null)");
            sql.execute("create table sales (id varchar(36) primary key, delivery_status varchar(20) not null, payment_status varchar(20) not null)");
            sql.execute("insert into products values ('product-test', 'Ovos')");
            sql.execute("insert into sales values ('sale-test', 'DELIVERED', 'PAID')");
        }
        Flyway flyway = Flyway.configure().dataSource(url, "sa", "")
                .locations("classpath:db/migration").baselineOnMigrate(true).baselineVersion("16").target("17").load();
        assertThat(flyway.migrate().migrationsExecuted).isEqualTo(1);
        assertThat(flyway.migrate().migrationsExecuted).isZero();
        try (var connection = DriverManager.getConnection(url, "sa", ""); var sql = connection.createStatement()) {
            try (var rows = sql.executeQuery("select name, minimum_stock from products where id='product-test'")) {
                assertThat(rows.next()).isTrue();
                assertThat(rows.getString(1)).isEqualTo("Ovos");
                assertThat(rows.getBigDecimal(2)).isNull();
            }
            try (var rows = sql.executeQuery("select delivery_status, payment_status, delivered_at, paid_at, cancelled_at from sales where id='sale-test'")) {
                assertThat(rows.next()).isTrue();
                assertThat(rows.getString(1)).isEqualTo("DELIVERED");
                assertThat(rows.getString(2)).isEqualTo("PAID");
                assertThat(rows.getTimestamp(3)).isNull();
                assertThat(rows.getTimestamp(4)).isNull();
                assertThat(rows.getTimestamp(5)).isNull();
            }
        }
    }
}
