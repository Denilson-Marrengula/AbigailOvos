package com.abigailovos.security;

import java.sql.DriverManager;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import static org.assertj.core.api.Assertions.*;

/** Only an empty, explicitly isolated local MySQL schema containing synthetic data. */
@EnabledIfEnvironmentVariable(named = "ABIGAIL_MYSQL_V14_PORT", matches = "[0-9]+")
class AuthenticatorMysqlMigrationTest {
    private String url() {
        return "jdbc:mysql://127.0.0.1:" + System.getenv("ABIGAIL_MYSQL_V14_PORT") + "/abigailovos_mfa_v14_isolated";
    }

    private Flyway flyway(String target) {
        return Flyway.configure().dataSource(url(), "root", "").locations("classpath:db/migration")
                .target(target).load();
    }

    @Test void v14ThroughV16AddOnlySecurityStorageAndPreserveExistingData() throws Exception {
        assertThat(flyway("13").migrate().migrationsExecuted).isEqualTo(13);
        try (var connection = DriverManager.getConnection(url(), "root", ""); var sql = connection.createStatement()) {
            sql.executeUpdate("insert into app_users (id,username,password_hash,role,enabled,created_at,session_epoch) values ('admin-id','admin_test','test-hash','ADMIN',true,now(6),4)");
            sql.executeUpdate("insert into auth_sessions (token_hash,account_id,account_epoch,created_at,last_seen_at,expires_at) values ('synthetic-hash','admin-id',4,now(6),now(6),now(6))");
        }
        assertThat(flyway("14").migrate().migrationsExecuted).isEqualTo(1);
        assertThat(flyway("14").migrate().migrationsExecuted).isZero();
        try (var connection = DriverManager.getConnection(url(), "root", ""); var sql = connection.createStatement()) {
            try (var result = sql.executeQuery("select username,password_hash,session_epoch from app_users where id='admin-id'")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getString(1)).isEqualTo("admin_test");
                assertThat(result.getString(2)).isEqualTo("test-hash");
                assertThat(result.getLong(3)).isEqualTo(4);
            }
            try (var result = sql.executeQuery("select count(*) from auth_sessions where account_id='admin-id'")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getInt(1)).isEqualTo(1);
            }
            try (var result = sql.executeQuery("select count(*) from admin_authenticators")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getInt(1)).isZero();
            }
            sql.executeUpdate("insert into admin_authenticators (account_id,active_secret,last_accepted_step) values ('admin-id','synthetic-envelope',3)");
            assertThatThrownBy(() -> sql.executeUpdate("insert into admin_authenticators (account_id,last_accepted_step) values ('missing-id',-1)"))
                    .isInstanceOf(java.sql.SQLException.class);
        }
        assertThat(flyway("15").migrate().migrationsExecuted).isEqualTo(1);
        assertThat(flyway("15").migrate().migrationsExecuted).isZero();
        try (var connection = DriverManager.getConnection(url(), "root", ""); var sql = connection.createStatement()) {
            try (var result = sql.executeQuery("select a.password_hash,a.session_epoch,m.active_secret,s.token_hash from app_users a join admin_authenticators m on m.account_id=a.id join auth_sessions s on s.account_id=a.id where a.id='admin-id'")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getString(1)).isEqualTo("test-hash");
                assertThat(result.getLong(2)).isEqualTo(4);
                assertThat(result.getString(3)).isEqualTo("synthetic-envelope");
                assertThat(result.getString(4)).isEqualTo("synthetic-hash");
            }
            try (var result = sql.executeQuery("select count(*) from auth_account_attempts")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getInt(1)).isZero();
            }
            sql.executeUpdate("insert into auth_account_attempts (account_id,window_started_at,last_attempt_at,failure_count) values ('admin-id',now(6),now(6),2)");
            assertThatThrownBy(() -> sql.executeUpdate("insert into auth_account_attempts (account_id,window_started_at,last_attempt_at) values ('missing-id',now(6),now(6))"))
                    .isInstanceOf(java.sql.SQLException.class);
        }
        assertThat(flyway("16").migrate().migrationsExecuted).isEqualTo(1);
        assertThat(flyway("16").migrate().migrationsExecuted).isZero();
        try (var connection = DriverManager.getConnection(url(), "root", ""); var sql = connection.createStatement()) {
            try (var result = sql.executeQuery("select entry_count from auth_origin_throttle_meta where id='global'")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getInt(1)).isZero();
                assertThat(result.next()).isFalse();
            }
            try (var result = sql.executeQuery("select failure_count from auth_account_attempts where account_id='admin-id'")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getInt(1)).isEqualTo(2);
            }
            try (var result = sql.executeQuery("select active_secret from admin_authenticators where account_id='admin-id'")) {
                assertThat(result.next()).isTrue();
                assertThat(result.getString(1)).isEqualTo("synthetic-envelope");
            }
        }
    }
}
