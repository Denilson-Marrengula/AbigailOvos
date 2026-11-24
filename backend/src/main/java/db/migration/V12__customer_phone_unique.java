package db.migration;

import com.abigailovos.customer.CustomerPhoneV1;
import java.sql.Connection;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import org.flywaydb.core.api.FlywayException;
import org.flywaydb.core.api.migration.BaseJavaMigration;
import org.flywaydb.core.api.migration.Context;

/** Requires writes to be suspended and all legacy phones to be reconciled first. */
public class V12__customer_phone_unique extends BaseJavaMigration {
    @Override public Integer getChecksum() { return 12001; }

    @Override
    public void migrate(Context context) throws Exception {
        Connection connection = context.getConnection();
        Map<String, String> keysById = new LinkedHashMap<>();
        Set<String> keys = new HashSet<>();
        int invalid = 0;
        int duplicates = 0;
        try (var select = connection.createStatement();
                var rows = select.executeQuery("SELECT id, phone FROM customers")) {
            while (rows.next()) {
                String key;
                try {
                    key = CustomerPhoneV1.canonical(rows.getString("phone"));
                } catch (IllegalArgumentException ex) {
                    invalid++;
                    continue;
                }
                if (!keys.add(key)) duplicates++;
                keysById.put(rows.getString("id"), key);
            }
        }
        // Do not expose personal data or make any schema changes before this check.
        if (invalid > 0 || duplicates > 0) {
            throw new FlywayException("Migração recusada: " + invalid
                    + " contacto(s) em falta ou inválido(s) e " + duplicates
                    + " número(s) repetido(s). Reconciliar os registos antes de avançar.");
        }
        try (var ddl = connection.createStatement()) {
            ddl.execute("ALTER TABLE customers ADD COLUMN phone_key VARCHAR(16) NULL");
        }
        try (var update = connection.prepareStatement("UPDATE customers SET phone_key = ? WHERE id = ?")) {
            for (var entry : keysById.entrySet()) {
                update.setString(1, entry.getValue());
                update.setString(2, entry.getKey());
                if (update.executeUpdate() != 1) throw new FlywayException("Os clientes mudaram durante a migração.");
            }
        }
        try (var ddl = connection.createStatement()) {
            ddl.execute("CREATE UNIQUE INDEX uk_customer_phone_key ON customers(phone_key)");
            ddl.execute("ALTER TABLE customers MODIFY COLUMN phone_key VARCHAR(16) NOT NULL");
        }
    }
}
