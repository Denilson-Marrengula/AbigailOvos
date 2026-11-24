package com.abigailovos.security;

import java.sql.DriverManager;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import static org.assertj.core.api.Assertions.*;

/** Only an empty, explicitly isolated local MySQL schema containing synthetic data. */
@EnabledIfEnvironmentVariable(named = "ABIGAIL_MYSQL_V13_PORT", matches = "[0-9]+")
class RevocableSessionsMysqlMigrationTest {
    private String url() {
        return "jdbc:mysql://127.0.0.1:" + System.getenv("ABIGAIL_MYSQL_V13_PORT") + "/abigailovos_sessions_v13_isolated";
    }

    private Flyway flyway(String target) {
        return Flyway.configure().dataSource(url(), "root", "").locations("classpath:db/migration")
                .target(target).load();
    }

    @Test void v13PreservesExistingAccountsAndStartsWithNoSessions() throws Exception {
        assertThat(flyway("12").migrate().migrationsExecuted).isEqualTo(12);
        try (var connection = DriverManager.getConnection(url(), "root", ""); var sql = connection.createStatement()) {
            sql.executeUpdate("insert into app_users (id,username,password_hash,role,enabled,created_at,must_change_password) values ('seller-id','seller_test','original-hash','SELLER',true,now(6),false)");
        }
        assertThat(flyway("13").migrate().migrationsExecuted).isEqualTo(1);
        assertThat(flyway("13").migrate().migrationsExecuted).isZero();
        try (var connection = DriverManager.getConnection(url(), "root", ""); var sql = connection.createStatement()) {
            try (var result = sql.executeQuery("select username,password_hash,enabled,session_epoch from app_users where id='seller-id'")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getString(1)).isEqualTo("seller_test");
                assertThat(result.getString(2)).isEqualTo("original-hash");
                assertThat(result.getBoolean(3)).isTrue();
                assertThat(result.getLong(4)).isZero();
            }
            try (var result = sql.executeQuery("select count(*) from auth_sessions")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getInt(1)).isZero();
            }
            sql.executeUpdate("insert into auth_sessions (token_hash,account_id,account_epoch,created_at,last_seen_at,expires_at) values ('synthetic-hash','seller-id',0,now(6),now(6),now(6))");
            assertThatThrownBy(() -> sql.executeUpdate("insert into auth_sessions (token_hash,account_id,account_epoch,created_at,last_seen_at,expires_at) values ('other-hash','missing-id',0,now(6),now(6),now(6))"))
                    .isInstanceOf(java.sql.SQLException.class);
        }
    }
}
