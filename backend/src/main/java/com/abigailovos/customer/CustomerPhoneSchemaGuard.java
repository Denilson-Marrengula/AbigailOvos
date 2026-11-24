package com.abigailovos.customer;

import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import javax.sql.DataSource;
import org.springframework.beans.factory.SmartInitializingSingleton;
import org.springframework.stereotype.Component;

/** Hibernate schema validation does not itself prove a unique index exists. */
@Component
class CustomerPhoneSchemaGuard implements SmartInitializingSingleton {
    private final DataSource source;
    CustomerPhoneSchemaGuard(DataSource source) { this.source = source; }

    @Override public void afterSingletonsInstantiated() { verify(source); }

    static void verify(DataSource source) {
        try (Connection connection = source.getConnection()) {
            DatabaseMetaData meta = connection.getMetaData();
            String catalog = connection.getCatalog();
            if (catalog == null || catalog.isBlank()) throw new IllegalStateException("Catálogo não identificado");
            String schema = "H2".equalsIgnoreCase(meta.getDatabaseProductName()) ? connection.getSchema() : null;
            String table = meta.storesUpperCaseIdentifiers() ? "CUSTOMERS" : "customers";
            String column = meta.storesUpperCaseIdentifiers() ? "PHONE_KEY" : "phone_key";
            boolean required = false;
            try (var rows = meta.getColumns(catalog, schema, table, column)) {
                while (rows.next()) {
                    if (column.equalsIgnoreCase(rows.getString("COLUMN_NAME"))
                            && rows.getInt("NULLABLE") == DatabaseMetaData.columnNoNulls) required = true;
                }
            }
            Map<String, List<String>> uniqueIndexes = new HashMap<>();
            try (var rows = meta.getIndexInfo(catalog, schema, table, true, false)) {
                while (rows.next()) {
                    String index = rows.getString("INDEX_NAME");
                    if (index == null || rows.getBoolean("NON_UNIQUE")) continue;
                    String indexedColumn = rows.getString("COLUMN_NAME");
                    uniqueIndexes.computeIfAbsent(index, ignored -> new ArrayList<>())
                            .add(indexedColumn == null ? "" : indexedColumn.toLowerCase(Locale.ROOT));
                }
            }
            boolean unique = uniqueIndexes.values().stream().anyMatch(columns -> columns.equals(List.of("phone_key")));
            if (!required || !unique) throw new IllegalStateException("Índice único de telefone ausente ou incompleto");
        } catch (SQLException error) {
            throw new IllegalStateException("Não foi possível verificar a proteção dos telefones dos clientes.");
        }
    }
}
