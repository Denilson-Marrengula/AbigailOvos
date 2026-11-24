package com.abigailovos.security;

import java.sql.DriverManager;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import static org.assertj.core.api.Assertions.*;

/** Run only against two new, explicitly isolated local databases with synthetic data. */
@EnabledIfEnvironmentVariable(named = "ABIGAIL_MYSQL_V9_PORT", matches = "[0-9]+")
class IsolatedMysqlMigrationTest {
    private String url(String schema) {
        return "jdbc:mysql://127.0.0.1:" + System.getenv("ABIGAIL_MYSQL_V9_PORT") + "/" + schema;
    }

    private Flyway flyway(String schema, String target) {
        var config = Flyway.configure().dataSource(url(schema), "root", "")
                .locations("classpath:db/migration");
        if (target != null) config.target(target);
        return config.load();
    }

    @Test void upgradesExistingVersionEightAndPreservesHistory() throws Exception {
        String schema = "abigailovos_v9_isolated_ok";
        assertThat(flyway(schema, "8").migrate().migrationsExecuted).isEqualTo(8);
        try (var connection = DriverManager.getConnection(url(schema), "root", "");
             var sql = connection.createStatement()) {
            sql.executeUpdate("insert into app_users (id,username,password_hash,role,enabled,created_at,display_name) values ('u1','Ana','test','SELLER',true,now(6),'Ana Teste')");
            sql.executeUpdate("insert into products (id,name,unit,price,created_at,updated_at,active) values ('p1','Ovos','bandeja',12.50,now(6),now(6),true)");
            sql.executeUpdate("insert into customers (id,name,created_at,updated_at) values ('c1','Cliente teste',now(6),now(6))");
            sql.executeUpdate("insert into sales (id,request_hash,customer_id,seller,delivery_status,payment_status,total,created_at,updated_at,updated_by) values ('s1','hash','c1','Ana','DELIVERED','PENDING',12.50,now(6),now(6),'Ana')");
            sql.executeUpdate("insert into sale_items (id,sale_id,product_id,product_name,unit,quantity,unit_price) values ('i1','s1','p1','Ovos','bandeja',1,12.50)");
            sql.executeUpdate("insert into stock_movements (id,product_id,administrator,movement_type,direction,quantity,reason,occurred_at) values ('m1','p1','Ana','ENTRY','INCREASE',2,'teste',now(6))");
        }
        assertThat(flyway(schema, "9").migrate().migrationsExecuted).isEqualTo(1);
        try (var connection = DriverManager.getConnection(url(schema), "root", "");
             var sql = connection.createStatement()) {
            try (var result = sql.executeQuery("select username_key, account_id from reserved_usernames")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getString(1)).isEqualTo("ana");
                assertThat(result.getString(2)).isEqualTo("u1");
                assertThat(result.next()).isFalse();
            }
            try (var result = sql.executeQuery("select s.seller, s.total, i.product_name, m.administrator from sales s join sale_items i on i.sale_id=s.id join stock_movements m on m.product_id=i.product_id where s.id='s1'")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getString(1)).isEqualTo("Ana");
                assertThat(result.getBigDecimal(2)).isEqualByComparingTo("12.50");
                assertThat(result.getString(3)).isEqualTo("Ovos");
                assertThat(result.getString(4)).isEqualTo("Ana");
            }
        }
    }

    @Test void caseCollisionStopsMigrationWithoutDeletingSourceAccounts() throws Exception {
        String schema = "abigailovos_v9_isolated_collision";
        assertThat(flyway(schema, "8").migrate().migrationsExecuted).isEqualTo(8);
        try (var connection = DriverManager.getConnection(url(schema), "root", "");
             var sql = connection.createStatement()) {
            sql.executeUpdate("alter table app_users modify username varchar(100) character set utf8mb4 collate utf8mb4_bin not null");
            sql.executeUpdate("insert into app_users (id,username,password_hash,role,enabled,created_at) values ('u1','Ana','test','SELLER',true,now(6)),('u2','ANA','test','SELLER',true,now(6))");
        }
        assertThatThrownBy(() -> flyway(schema, "9").migrate()).isInstanceOf(RuntimeException.class);
        try (var connection = DriverManager.getConnection(url(schema), "root", "");
             var sql = connection.createStatement();
             var result = sql.executeQuery("select count(*) from app_users")) {
            assertThat(result.next()).isTrue();
            assertThat(result.getInt(1)).isEqualTo(2);
        }
    }

    @Test void v10AndV11PreserveSalesAndExistingCredentials() throws Exception {
        String schema = "abigailovos_v10_isolated";
        assertThat(flyway(schema, "9").migrate().migrationsExecuted).isEqualTo(9);
        try (var connection = DriverManager.getConnection(url(schema), "root", "");
             var sql = connection.createStatement()) {
            sql.executeUpdate("insert into app_users (id,username,password_hash,role,enabled,created_at) values ('u1','ana','test','SELLER',true,now(6))");
            sql.executeUpdate("insert into products (id,name,unit,price,created_at,updated_at,active) values ('p1','Ovos','bandeja',12.50,now(6),now(6),true)");
            sql.executeUpdate("insert into customers (id,name,created_at,updated_at) values ('c1','Cliente teste',now(6),now(6))");
            sql.executeUpdate("insert into sales (id,request_hash,customer_id,seller,delivery_status,payment_status,total,created_at,updated_at,updated_by) values ('s1','old-hash','c1','ana','PENDING','PAID',12.50,now(6),now(6),'ana'),('s2','old-hash-2','c1','ana','PENDING','PENDING',25.00,now(6),now(6),'ana')");
            sql.executeUpdate("insert into sale_items (id,sale_id,product_id,product_name,unit,quantity,unit_price) values ('i1','s1','p1','Ovos','bandeja',1,12.50),('i2','s2','p1','Ovos','bandeja',2,12.50)");
            sql.executeUpdate("insert into stock_movements (id,product_id,administrator,movement_type,direction,quantity,reason,occurred_at) values ('m1','p1','ana','ENTRY','INCREASE',5,'teste',now(6))");
        }
        assertThat(flyway(schema, "10").migrate().migrationsExecuted).isEqualTo(1);
        assertThat(flyway(schema, "10").migrate().migrationsExecuted).isZero();
        try (var connection = DriverManager.getConnection(url(schema), "root", "");
             var sql = connection.createStatement()) {
            try (var result = sql.executeQuery("select id, request_hash, payment_status, payment_method, total from sales order by id")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getString(1)).isEqualTo("s1");
                assertThat(result.getString(2)).isEqualTo("old-hash");
                assertThat(result.getString(3)).isEqualTo("PAID");
                assertThat(result.getString(4)).isNull();
                assertThat(result.getBigDecimal(5)).isEqualByComparingTo("12.50");
                assertThat(result.next()).isTrue();
                assertThat(result.getString(1)).isEqualTo("s2");
                assertThat(result.getString(3)).isEqualTo("PENDING");
                assertThat(result.getString(4)).isNull();
                assertThat(result.getBigDecimal(5)).isEqualByComparingTo("25.00");
                assertThat(result.next()).isFalse();
            }
            try (var result = sql.executeQuery("select sum(quantity) from sale_items")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getBigDecimal(1)).isEqualByComparingTo("3");
            }
            try (var result = sql.executeQuery("select quantity from stock_movements where id='m1'")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getBigDecimal(1)).isEqualByComparingTo("5");
            }
            sql.executeUpdate("update sales set payment_status='PAID', payment_method='MPESA' where id='s2'");
            try (var result = sql.executeQuery("select payment_method from sales where id='s2'")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getString(1)).isEqualTo("MPESA");
            }
        }
        assertThat(flyway(schema, "11").migrate().migrationsExecuted).isEqualTo(1);
        assertThat(flyway(schema, "11").migrate().migrationsExecuted).isZero();
        try (var connection = DriverManager.getConnection(url(schema), "root", "");
             var sql = connection.createStatement();
             var result = sql.executeQuery("select username, password_hash, must_change_password, temporary_password_expires_at from app_users where id='u1'")) {
            assertThat(result.next()).isTrue();
            assertThat(result.getString(1)).isEqualTo("ana");
            assertThat(result.getString(2)).isEqualTo("test");
            assertThat(result.getBoolean(3)).isFalse();
            assertThat(result.getTimestamp(4)).isNull();
        }
        try (var connection = DriverManager.getConnection(url(schema), "root", "");
             var sql = connection.createStatement();
             var result = sql.executeQuery("select seller, payment_status, payment_method, total from sales where id='s2'")) {
            assertThat(result.next()).isTrue();
            assertThat(result.getString(1)).isEqualTo("ana");
            assertThat(result.getString(2)).isEqualTo("PAID");
            assertThat(result.getString(3)).isEqualTo("MPESA");
            assertThat(result.getBigDecimal(4)).isEqualByComparingTo("25.00");
        }
    }
}
