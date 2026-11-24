package com.abigailovos.customer;

import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class CustomerPhoneSchemaGuardTest {
    @Test void requiresANonNullSingleColumnUniqueIndex() {
        var source = new DriverManagerDataSource("jdbc:h2:mem:guard_" + UUID.randomUUID().toString().replace("-", "") + ";DB_CLOSE_DELAY=-1", "sa", "");
        var jdbc = new JdbcTemplate(source);
        jdbc.execute("create table customers (id varchar(36) not null primary key, phone_key varchar(16), extra varchar(16))");
        assertThatThrownBy(() -> CustomerPhoneSchemaGuard.verify(source)).isInstanceOf(IllegalStateException.class);
        jdbc.execute("create unique index uk_composite on customers(phone_key, extra)");
        assertThatThrownBy(() -> CustomerPhoneSchemaGuard.verify(source)).isInstanceOf(IllegalStateException.class);
        jdbc.execute("create unique index uk_phone on customers(phone_key)");
        assertThatThrownBy(() -> CustomerPhoneSchemaGuard.verify(source)).isInstanceOf(IllegalStateException.class);
        jdbc.execute("alter table customers alter column phone_key set not null");
        assertThatCode(() -> CustomerPhoneSchemaGuard.verify(source)).doesNotThrowAnyException();
    }
}
