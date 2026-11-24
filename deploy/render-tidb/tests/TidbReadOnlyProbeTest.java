import java.lang.reflect.Proxy;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.DriverPropertyInfo;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

/** Synthetic driver stubs; no network connection or credentials. */
public final class TidbReadOnlyProbeTest {
    private static final String SCHEMA = "abigailovos_tidb_test_1234abcd";

    private static void require(boolean condition) {
        if (!condition) throw new AssertionError("Teste sintetico falhou.");
    }

    private static void rejects(String host, int port, String schema) {
        try {
            TidbReadOnlyProbe.jdbcUrl(host, port, schema);
            throw new AssertionError("Destino invalido aceite.");
        } catch (IllegalArgumentException expected) {
            // Expected.
        }
    }

    private static ResultSet result(Object[] values) {
        boolean[] first = {true};
        return (ResultSet) Proxy.newProxyInstance(ResultSet.class.getClassLoader(),
                new Class<?>[]{ResultSet.class}, (proxy, method, args) -> switch (method.getName()) {
                    case "next" -> { boolean value = first[0]; first[0] = false; yield value; }
                    case "getString" -> values[(int) args[0] - 1];
                    case "getInt" -> ((Number) values[(int) args[0] - 1]).intValue();
                    case "getLong" -> ((Number) values[(int) args[0] - 1]).longValue();
                    case "close" -> null;
                    default -> throw new UnsupportedOperationException(method.getName());
                });
    }

    private static Connection fake(String schema, String mode, int foreignKeys, long count, List<String> queries) {
        return (Connection) Proxy.newProxyInstance(Connection.class.getClassLoader(),
                new Class<?>[]{Connection.class}, (proxy, method, args) -> switch (method.getName()) {
                    case "createStatement" -> Proxy.newProxyInstance(Statement.class.getClassLoader(),
                            new Class<?>[]{Statement.class}, (p, m, a) -> switch (m.getName()) {
                                case "executeQuery" -> {
                                    String sql = (String) a[0];
                                    queries.add(sql);
                                    if (sql.equals("SELECT DATABASE(), @@tidb_txn_mode, @@foreign_key_checks")) {
                                        yield result(new Object[]{schema, mode, foreignKeys});
                                    }
                                    if (sql.equals("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()")) {
                                        yield result(new Object[]{count});
                                    }
                                    throw new SQLException("Consulta inesperada.");
                                }
                                case "close" -> null;
                                default -> throw new UnsupportedOperationException(m.getName());
                            });
                    case "close" -> null;
                    default -> throw new UnsupportedOperationException(method.getName());
                });
    }

    public static void main(String[] args) throws Exception {
        String url = TidbReadOnlyProbe.jdbcUrl("gateway.example.tidbcloud.com", 4000, SCHEMA);
        require(url.equals("jdbc:mysql://gateway.example.tidbcloud.com:4000/" + SCHEMA
                + "?sslMode=VERIFY_IDENTITY&connectTimeout=15000&socketTimeout=30000"));
        // Parse configuration with the actual Connector/J driver. No connect() call.
        DriverPropertyInfo[] properties = DriverManager.getDriver(url).getPropertyInfo(url, new Properties());
        boolean verifiedIdentity = false;
        for (DriverPropertyInfo property : properties) {
            if ("sslMode".equals(property.name)) {
                verifiedIdentity = "VERIFY_IDENTITY".equals(property.value);
            }
        }
        require(verifiedIdentity);
        rejects("tidbcloud.com", 4000, SCHEMA);
        rejects("example.tidbcloud.com.attacker.example", 4000, SCHEMA);
        rejects("root:secret@example.tidbcloud.com", 4000, SCHEMA);
        rejects("example.tidbcloud.com?sslMode=DISABLED", 4000, SCHEMA);
        rejects("example.tidbcloud.com", 0, SCHEMA);
        rejects("example.tidbcloud.com", 4000, "production");
        rejects("example.tidbcloud.com", 4000, "abigailovos_tidb_test_4292b79106cb4fac");
        require(TidbReadOnlyProbe.isRootUser("Prefix123.root"));
        require(!TidbReadOnlyProbe.isRootUser("Prefix123.root?password=x"));

        List<String> queries = new ArrayList<>();
        require(TidbReadOnlyProbe.inspect(fake(SCHEMA, "pessimistic", 1, 0, queries), SCHEMA));
        require(queries.size() == 2 && queries.stream().allMatch(q -> q.startsWith("SELECT ")));
        require(!TidbReadOnlyProbe.inspect(fake("other", "pessimistic", 1, 0, new ArrayList<>()), SCHEMA));
        require(!TidbReadOnlyProbe.inspect(fake(SCHEMA, "optimistic", 1, 0, new ArrayList<>()), SCHEMA));
        require(!TidbReadOnlyProbe.inspect(fake(SCHEMA, "pessimistic", 0, 0, new ArrayList<>()), SCHEMA));
        require(!TidbReadOnlyProbe.inspect(fake(SCHEMA, "pessimistic", 1, 1, new ArrayList<>()), SCHEMA));
        System.out.println("Validacoes sinteticas concluidas; nenhuma ligacao foi feita.");
    }
}
