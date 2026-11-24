import java.lang.reflect.Proxy;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

/** Synthetic tests only; all database objects are in-memory JDBC proxies. */
public final class TidbTestAccountSetupTest {
    private static final String USER = "Prefix123.t0f90d8";
    private static final String USAGE = "GRANT USAGE ON *.* TO '" + USER + "'@'%'";
    private static final String PRIVILEGES = "SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES";
    private static final String SCOPED = "GRANT " + PRIVILEGES + " ON "
            + TidbTestAccountSetup.escapedSchema() + ".* TO '" + USER + "'@'%'";

    private static void require(boolean condition) {
        if (!condition) throw new AssertionError("Teste sintetico falhou.");
    }

    private static void rejects(Runnable operation) {
        try {
            operation.run();
            throw new AssertionError("Entrada insegura aceite.");
        } catch (IllegalArgumentException expected) {
            // Expected.
        }
    }

    private static ResultSet result(List<Object[]> rows) {
        int[] index = {-1};
        return (ResultSet) Proxy.newProxyInstance(ResultSet.class.getClassLoader(),
                new Class<?>[]{ResultSet.class}, (proxy, method, args) -> switch (method.getName()) {
                    case "next" -> ++index[0] < rows.size();
                    case "getString" -> rows.get(index[0])[(int) args[0] - 1];
                    case "getInt" -> ((Number) rows.get(index[0])[(int) args[0] - 1]).intValue();
                    case "getLong" -> ((Number) rows.get(index[0])[(int) args[0] - 1]).longValue();
                    case "close" -> null;
                    default -> throw new UnsupportedOperationException(method.getName());
                });
    }

    private static Connection fake(String schema, String mode, int foreignKeys, long tables,
            List<String> grants, List<String> reads, List<String> writes) {
        return (Connection) Proxy.newProxyInstance(Connection.class.getClassLoader(),
                new Class<?>[]{Connection.class}, (proxy, method, args) -> switch (method.getName()) {
                    case "createStatement" -> Proxy.newProxyInstance(Statement.class.getClassLoader(),
                            new Class<?>[]{Statement.class}, (p, m, a) -> switch (m.getName()) {
                                case "executeUpdate" -> { writes.add((String) a[0]); yield 1; }
                                case "executeQuery" -> {
                                    String sql = (String) a[0];
                                    reads.add(sql);
                                    if (sql.equals("SELECT DATABASE(), @@tidb_txn_mode, @@foreign_key_checks")) {
                                        yield result(List.<Object[]>of(new Object[]{schema, mode, foreignKeys}));
                                    }
                                    if (sql.equals("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()")) {
                                        yield result(List.<Object[]>of(new Object[]{tables}));
                                    }
                                    if (sql.equals("SHOW GRANTS FOR '" + USER + "'@'%'")) {
                                        yield result(grants.stream().map(value -> new Object[]{value}).toList());
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

    private static Connection pilotFake(boolean allow, int code, String state, List<String> reads) {
        return (Connection) Proxy.newProxyInstance(Connection.class.getClassLoader(),
                new Class<?>[]{Connection.class}, (proxy, method, args) -> switch (method.getName()) {
                    case "createStatement" -> Proxy.newProxyInstance(Statement.class.getClassLoader(),
                            new Class<?>[]{Statement.class}, (p, m, a) -> switch (m.getName()) {
                                case "executeQuery" -> {
                                    reads.add((String) a[0]);
                                    if (!allow) throw new SQLException("Erro sintetico", state, code);
                                    yield result(List.of());
                                }
                                case "close" -> null;
                                default -> throw new UnsupportedOperationException(m.getName());
                            });
                    case "close" -> null;
                    default -> throw new UnsupportedOperationException(method.getName());
                });
    }

    public static void main(String[] args) throws Exception {
        String url = TidbTestAccountSetup.jdbcUrl("gateway.example.tidbcloud.com", 4000);
        require(url.equals("jdbc:mysql://gateway.example.tidbcloud.com:4000/" + TidbTestAccountSetup.TEST_SCHEMA
                + "?sslMode=VERIFY_IDENTITY&connectTimeout=15000&socketTimeout=30000"));
        rejects(() -> TidbTestAccountSetup.jdbcUrl("example.tidbcloud.com.attacker.example", 4000));
        rejects(() -> TidbTestAccountSetup.jdbcUrl("name:secret@example.tidbcloud.com", 4000));
        rejects(() -> TidbTestAccountSetup.jdbcUrl("example.tidbcloud.com?sslMode=DISABLED", 4000));
        rejects(() -> TidbTestAccountSetup.jdbcUrl("example.tidbcloud.com", 0));
        require(USER.equals(TidbTestAccountSetup.testUser("Prefix123.root")));
        require(TidbTestAccountSetup.testUser("abcdefghijklmnopqrstuvwx.root").length() == 32);
        rejects(() -> TidbTestAccountSetup.testUser("Prefix123.root'@'%"));
        rejects(() -> TidbTestAccountSetup.testUser("root"));
        require(TidbTestAccountSetup.validPassword("aB9cD8eF7gH6iJ5kL4mN3pQ2rS1tU0vW".toCharArray()));
        require(!TidbTestAccountSetup.validPassword("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".toCharArray()));
        require(!TidbTestAccountSetup.validPassword("short".toCharArray()));
        require(!TidbTestAccountSetup.validPassword("aB9cD8eF7gH6iJ5kL4mN3pQ2rS1tU0v!".toCharArray()));

        String verifier = TidbTestAccountSetup.nativeVerifier("test".toCharArray());
        require("*94BDCEBE19083CE2A1F959FD02F964C7AF4CFC29".equals(verifier));
        String create = TidbTestAccountSetup.createUserSql(USER, verifier);
        require(create.startsWith("CREATE USER '" + USER + "'@'%' IDENTIFIED WITH 'mysql_native_password' AS '"));
        require(create.endsWith("' REQUIRE SSL") && !create.contains("'test'"));
        rejects(() -> TidbTestAccountSetup.createUserSql("root", verifier));
        rejects(() -> TidbTestAccountSetup.createUserSql(USER, "' OR 1=1 --"));
        String grant = TidbTestAccountSetup.grantSql(USER);
        require(grant.equals(SCOPED));
        require(grant.contains("`abigailovos\\_tidb\\_test\\_0f90d84d9d5245e1`.*"));
        require(!grant.contains("4292b79106cb4fac") && !grant.contains("GRANT OPTION"));
        rejects(() -> TidbTestAccountSetup.grantSql("Prefix123.root"));

        require(TidbTestAccountSetup.exactGrants(List.of(USAGE, SCOPED), USER));
        require(TidbTestAccountSetup.exactGrants(List.of(SCOPED, USAGE), USER));
        require(!TidbTestAccountSetup.exactGrants(List.of(USAGE, SCOPED + " WITH GRANT OPTION"), USER));
        require(!TidbTestAccountSetup.exactGrants(List.of(USAGE, SCOPED.replace("\\_", "_")), USER));
        require(!TidbTestAccountSetup.exactGrants(List.of(USAGE, SCOPED.replace("REFERENCES", "REFERENCES, DROP")), USER));
        require(!TidbTestAccountSetup.exactGrants(List.of(USAGE, SCOPED.replace(", REFERENCES", "")), USER));
        require(!TidbTestAccountSetup.exactGrants(List.of(USAGE, SCOPED, "GRANT 'role'@'%' TO '" + USER + "'@'%'"), USER));
        require(!TidbTestAccountSetup.exactGrants(List.of(USAGE, SCOPED.replace(TidbTestAccountSetup.escapedSchema() + ".*", "*.*")), USER));
        require(!TidbTestAccountSetup.exactGrants(List.of(USAGE, SCOPED), "Prefix123.root"));

        List<String> reads = new ArrayList<>();
        List<String> writes = new ArrayList<>();
        Connection fake = fake(TidbTestAccountSetup.TEST_SCHEMA, "pessimistic", 1, 0,
                List.of(USAGE, SCOPED), reads, writes);
        require(TidbTestAccountSetup.preflight(fake));
        require(writes.isEmpty() && reads.size() == 2 && reads.stream().allMatch(q -> q.startsWith("SELECT ")));
        TidbTestAccountSetup.createAccount(fake, USER, verifier);
        TidbTestAccountSetup.grantTestPrivileges(fake, USER);
        require(TidbTestAccountSetup.verifyGrants(fake, USER));
        require(writes.equals(List.of(create, grant)));
        require(!TidbTestAccountSetup.preflight(fake("other", "pessimistic", 1, 0, List.of(), new ArrayList<>(), new ArrayList<>())));
        require(!TidbTestAccountSetup.preflight(fake(TidbTestAccountSetup.TEST_SCHEMA, "optimistic", 1, 0, List.of(), new ArrayList<>(), new ArrayList<>())));
        require(!TidbTestAccountSetup.preflight(fake(TidbTestAccountSetup.TEST_SCHEMA, "pessimistic", 0, 0, List.of(), new ArrayList<>(), new ArrayList<>())));
        require(!TidbTestAccountSetup.preflight(fake(TidbTestAccountSetup.TEST_SCHEMA, "pessimistic", 1, 1, List.of(), new ArrayList<>(), new ArrayList<>())));
        List<String> pilotReads = new ArrayList<>();
        require(TidbTestAccountSetup.pilotAccessDenied(pilotFake(false, 1044, "42000", pilotReads)));
        require(pilotReads.equals(List.of("SHOW TABLES FROM `" + TidbTestAccountSetup.PILOT_SCHEMA + "`")));
        require(!TidbTestAccountSetup.pilotAccessDenied(pilotFake(true, 0, null, new ArrayList<>())));
        try {
            TidbTestAccountSetup.pilotAccessDenied(pilotFake(false, 0, "08001", new ArrayList<>()));
            throw new AssertionError("Erro de ligacao nao e prova de isolamento.");
        } catch (SQLException expected) {
            require("08001".equals(expected.getSQLState()));
        }
        System.out.println("Testes sinteticos concluidos; nenhuma ligacao de rede ou alteracao na nuvem.");
    }
}
