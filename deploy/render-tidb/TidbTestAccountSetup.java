import java.io.Console;
import java.security.MessageDigest;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Properties;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Explicitly authorized setup for one isolated, fictitious TiDB schema only.
 * Do not run in an instance containing real or otherwise important data.
 * A partial failure can leave a user or grant behind; nothing is removed.
 */
public final class TidbTestAccountSetup {
    static final String TEST_SCHEMA = "abigailovos_tidb_test_0f90d84d9d5245e1";
    static final String PILOT_SCHEMA = "abigailovos_tidb_test_4292b79106cb4fac";
    private static final Pattern HOST = Pattern.compile(
            "(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+tidbcloud\\.com");
    private static final Pattern ROOT = Pattern.compile("[A-Za-z0-9]{1,24}\\.root");
    private static final Pattern TEST_USER = Pattern.compile("[A-Za-z0-9]{1,24}\\.t0f90d8");
    private static final Pattern NATIVE_HASH = Pattern.compile("\\*[0-9A-F]{40}");
    private static final Set<String> TEST_PRIVILEGES = Set.of(
            "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "INDEX", "REFERENCES");

    private TidbTestAccountSetup() { }

    static String jdbcUrl(String host, int port) {
        if (host == null || !HOST.matcher(host.toLowerCase(Locale.ROOT)).matches()
                || port < 1 || port > 65535) throw new IllegalArgumentException();
        return "jdbc:mysql://" + host.toLowerCase(Locale.ROOT) + ":" + port + "/" + TEST_SCHEMA
                + "?sslMode=VERIFY_IDENTITY&connectTimeout=15000&socketTimeout=30000";
    }

    static String testUser(String root) {
        if (root == null || !ROOT.matcher(root).matches()) throw new IllegalArgumentException();
        return root.substring(0, root.length() - ".root".length()) + ".t0f90d8";
    }

    static boolean validPassword(char[] password) {
        if (password == null || password.length < 32 || password.length > 96) return false;
        Set<Character> distinct = new HashSet<>();
        for (char c : password) {
            if (!(c >= 'a' && c <= 'z') && !(c >= 'A' && c <= 'Z') && !(c >= '0' && c <= '9')) {
                return false;
            }
            distinct.add(c);
        }
        // This is only a basic check, not proof of randomness. A password manager is required.
        return distinct.size() >= 16;
    }

    /** Send only the native verifier, never the plaintext password, in CREATE USER. */
    static String nativeVerifier(char[] password) throws Exception {
        byte[] bytes = new byte[password.length];
        byte[] first = null;
        byte[] second = null;
        try {
            for (int i = 0; i < password.length; i++) {
                if (password[i] > 127) throw new IllegalArgumentException();
                bytes[i] = (byte) password[i];
            }
            MessageDigest sha1 = MessageDigest.getInstance("SHA-1");
            first = sha1.digest(bytes);
            second = sha1.digest(first);
            return "*" + HexFormat.of().withUpperCase().formatHex(second);
        } finally {
            Arrays.fill(bytes, (byte) 0);
            if (first != null) Arrays.fill(first, (byte) 0);
            if (second != null) Arrays.fill(second, (byte) 0);
        }
    }

    static String createUserSql(String user, String verifier) {
        if (user == null || !TEST_USER.matcher(user).matches()
                || verifier == null || !NATIVE_HASH.matcher(verifier).matches()) throw new IllegalArgumentException();
        return "CREATE USER '" + user + "'@'%' IDENTIFIED WITH 'mysql_native_password' AS '"
                + verifier + "' REQUIRE SSL";
    }

    static String escapedSchema() {
        // TiDB database-level GRANT names are patterns: underscores must be literal.
        return "`" + TEST_SCHEMA.replace("_", "\\_") + "`";
    }

    static String grantSql(String user) {
        if (user == null || !TEST_USER.matcher(user).matches()) throw new IllegalArgumentException();
        return "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES ON "
                + escapedSchema() + ".* TO '" + user + "'@'%'";
    }

    /** Fail closed on extra roles, privileges, targets or unescaped database patterns. */
    static boolean exactGrants(List<String> grants, String user) {
        if (user == null || !TEST_USER.matcher(user).matches() || grants == null || grants.size() != 2) return false;
        String suffix = " TO '" + user + "'@'%'";
        boolean usage = false;
        boolean schemaGrant = false;
        for (String grant : grants) {
            if (grant == null) return false;
            String row = grant.strip();
            if (!row.endsWith(suffix) || !row.startsWith("GRANT ")) return false;
            String body = row.substring("GRANT ".length(), row.length() - suffix.length());
            int separator = body.indexOf(" ON ");
            if (separator < 0 || body.indexOf(" ON ", separator + 1) >= 0) return false;
            String privileges = body.substring(0, separator);
            String target = body.substring(separator + " ON ".length());
            if ("*.*".equals(target) && "USAGE".equals(privileges) && !usage) {
                usage = true;
            } else if ((escapedSchema() + ".*").equals(target) && !schemaGrant) {
                List<String> names = Arrays.stream(privileges.split(",", -1)).map(String::strip).toList();
                Set<String> unique = new HashSet<>(names);
                if (names.size() != TEST_PRIVILEGES.size() || !unique.equals(TEST_PRIVILEGES)) return false;
                schemaGrant = true;
            } else {
                return false;
            }
        }
        return usage && schemaGrant;
    }

    static boolean preflight(Connection connection) throws SQLException {
        try (Statement statement = connection.createStatement();
                ResultSet result = statement.executeQuery(
                        "SELECT DATABASE(), @@tidb_txn_mode, @@foreign_key_checks")) {
            if (!result.next() || !TEST_SCHEMA.equals(result.getString(1))
                    || !"pessimistic".equalsIgnoreCase(result.getString(2)) || result.getInt(3) != 1) return false;
        }
        try (Statement statement = connection.createStatement();
                ResultSet result = statement.executeQuery(
                        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()")) {
            return result.next() && result.getLong(1) == 0;
        }
    }

    static void createAccount(Connection connection, String user, String verifier) throws SQLException {
        try (Statement statement = connection.createStatement()) {
            // Deliberately no IF NOT EXISTS: never modify or reuse an existing account.
            statement.executeUpdate(createUserSql(user, verifier));
        }
    }

    static void grantTestPrivileges(Connection connection, String user) throws SQLException {
        try (Statement statement = connection.createStatement()) {
            statement.executeUpdate(grantSql(user));
        }
    }

    static boolean verifyGrants(Connection connection, String user) throws SQLException {
        if (user == null || !TEST_USER.matcher(user).matches()) throw new IllegalArgumentException();
        List<String> rows = new ArrayList<>();
        try (Statement statement = connection.createStatement();
                ResultSet result = statement.executeQuery("SHOW GRANTS FOR '" + user + "'@'%'")) {
            while (result.next()) rows.add(result.getString(1));
        }
        return exactGrants(rows, user);
    }

    /** A read-only negative check; unrelated errors do not prove access was denied. */
    static boolean pilotAccessDenied(Connection connection) throws SQLException {
        try (Statement statement = connection.createStatement()) {
            ResultSet result;
            try {
                result = statement.executeQuery("SHOW TABLES FROM `" + PILOT_SCHEMA + "`");
            } catch (SQLException ex) {
                if (ex.getErrorCode() == 1044 && "42000".equals(ex.getSQLState())) return true;
                throw ex;
            }
            try (result) {
                // Even an empty result means the listing was permitted.
                return false;
            }
        }
    }

    private static Connection connect(String url, String username, char[] password) throws SQLException {
        Properties properties = new Properties();
        try {
            properties.setProperty("user", username);
            // Connector/J requires a String, which remains in memory until collected.
            properties.setProperty("password", new String(password));
            return DriverManager.getConnection(url, properties);
        } finally {
            properties.remove("password");
        }
    }

    public static void main(String[] args) {
        if (run(System.console(), args) != 0) System.exit(1);
    }

    private static int run(Console console, String[] args) {
        if (console == null || args.length != 0) {
            System.err.println("Execute sem argumentos numa consola interativa privada.");
            return 1;
        }
        char[] adminPassword = null;
        char[] password = null;
        char[] passwordAgain = null;
        boolean attemptedCreate = false;
        boolean attemptedGrant = false;
        try {
            console.printf("Somente uma conta nova para a base ficticia %s.%n", TEST_SCHEMA);
            console.printf("Nao execute se a instancia tiver dados reais ou importantes.%n");
            console.printf("O acesso e apenas para ensaios; nao inicia migracoes nem cria tabelas.%n");
            console.printf("A verificacao tentara listar as tabelas da base do piloto; o acesso deve ser negado.%n");
            String host = console.readLine("Host da instancia de ensaio (sem https ou parametros): ");
            String port = console.readLine("Porta (Enter para 4000): ");
            String root = console.readLine("Conta administrativa completa terminada em .root: ");
            if (host == null || port == null || root == null) throw new IllegalArgumentException();
            String url = jdbcUrl(host.trim(), port.isBlank() ? 4000 : Integer.parseInt(port.trim()));
            root = root.trim();
            String user = testUser(root);
            console.printf("Conta nova a guardar em privado: %s%n", user);
            console.printf("Use uma palavra-passe aleatoria de gestor de senhas, com 32 a 96 letras/numeros.%n");
            console.printf("Guarde-a no gestor; nao a coloque nesta conversa ou no SQL Editor.%n");
            password = console.readPassword("Palavra-passe NOVA da conta de ensaio: ");
            passwordAgain = console.readPassword("Repita a palavra-passe NOVA: ");
            if (!validPassword(password) || !Arrays.equals(password, passwordAgain)) {
                console.printf("Palavra-passe invalida ou nao coincide; nenhuma conta foi criada.%n");
                return 1;
            }
            String confirmation = console.readLine("Para criar a conta e conceder permissoes na base ficticia, escreva CRIAR: ");
            if (!"CRIAR".equals(confirmation)) {
                console.printf("Operacao cancelada; nenhuma conta foi criada.%n");
                return 1;
            }
            adminPassword = console.readPassword("Palavra-passe da conta administrativa: ");
            if (adminPassword == null || adminPassword.length == 0) throw new IllegalArgumentException();
            String verifier = nativeVerifier(password);
            DriverManager.setLoginTimeout(20);
            try (Connection admin = connect(url, root, adminPassword)) {
                if (!preflight(admin)) {
                    console.printf("A base ou configuracao nao passou na verificacao; nenhuma conta foi criada.%n");
                    return 1;
                }
                attemptedCreate = true;
                createAccount(admin, user, verifier);
                attemptedGrant = true;
                grantTestPrivileges(admin, user);
                if (!verifyGrants(admin, user)) {
                    console.printf("Conta criada, mas as permissoes nao puderam ser confirmadas. Nao execute testes.%n");
                    return 1;
                }
            }
            try (Connection test = connect(url, user, password)) {
                if (!preflight(test)) {
                    console.printf("Conta criada, mas a ligacao de ensaio nao passou na verificacao. Nao execute testes.%n");
                    return 1;
                }
                if (!pilotAccessDenied(test)) {
                    console.printf("Conta criada, mas o acesso a base do piloto nao foi negado. Nao execute testes nem use dados reais.%n");
                    return 1;
                }
            }
            console.printf("Conta de ensaio criada; permissoes e recusas verificadas nesta sessao.%n");
            console.printf("Isto nao prova isolamento completo. Nao execute migracoes ou testes sem autorizacao.%n");
            return 0;
        } catch (Exception ignored) {
            // SQL/driver exceptions can contain credentials or endpoint details.
            if (attemptedCreate) {
                console.printf("Nao foi possivel concluir. A conta%s pode existir parcialmente; nao repita nem apague nada.%n",
                        attemptedGrant ? " ou a permissao" : "");
            } else {
                console.printf("Nao foi possivel concluir; este programa nao tentou criar a conta.%n");
            }
            return 1;
        } finally {
            if (adminPassword != null) Arrays.fill(adminPassword, '\0');
            if (password != null) Arrays.fill(password, '\0');
            if (passwordAgain != null) Arrays.fill(passwordAgain, '\0');
        }
    }
}
