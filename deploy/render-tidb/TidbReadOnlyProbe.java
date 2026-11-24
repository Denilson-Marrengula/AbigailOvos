import java.io.Console;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Arrays;
import java.util.Locale;
import java.util.Properties;
import java.util.regex.Pattern;

/**
 * Interactive, read-only preparation for an exclusively fictitious TiDB
 * instance. It does not prove instance ownership, least privilege, restore,
 * Render connectivity, or the correctness of migrations and transactions.
 * Never run against an instance containing real or otherwise important data.
 */
public final class TidbReadOnlyProbe {
    private static final Pattern HOST = Pattern.compile(
            "(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+tidbcloud\\.com");
    private static final Pattern SCHEMA = Pattern.compile("abigailovos_tidb_test_[a-z0-9]{8,32}");
    // Despite its name, this schema was selected by the owner for real operations.
    private static final String RESERVED_OPERATIONAL_SCHEMA = "abigailovos_tidb_test_4292b79106cb4fac";
    private static final Pattern ROOT_USER = Pattern.compile("[A-Za-z0-9]{1,24}\\.root");

    private TidbReadOnlyProbe() { }

    private static boolean isFictitiousSchema(String schema) {
        return schema != null && SCHEMA.matcher(schema).matches()
                && !RESERVED_OPERATIONAL_SCHEMA.equalsIgnoreCase(schema);
    }

    static String jdbcUrl(String host, int port, String schema) {
        if (host == null || !HOST.matcher(host.toLowerCase(Locale.ROOT)).matches()
                || port < 1 || port > 65535 || !isFictitiousSchema(schema)) {
            throw new IllegalArgumentException("Ligacao ou base invalida.");
        }
        return "jdbc:mysql://" + host.toLowerCase(Locale.ROOT) + ":" + port + "/" + schema
                + "?sslMode=VERIFY_IDENTITY&connectTimeout=15000&socketTimeout=30000";
    }

    static boolean isRootUser(String username) {
        return username != null && ROOT_USER.matcher(username).matches();
    }

    /** Only SELECT statements are used; a missing table count does not prove emptiness. */
    static boolean inspect(Connection connection, String schema) throws SQLException {
        try (Statement statement = connection.createStatement();
                ResultSet settings = statement.executeQuery(
                        "SELECT DATABASE(), @@tidb_txn_mode, @@foreign_key_checks")) {
            if (!settings.next() || !schema.equals(settings.getString(1))
                    || !"pessimistic".equalsIgnoreCase(settings.getString(2))
                    || settings.getInt(3) != 1) {
                return false;
            }
        }
        try (Statement statement = connection.createStatement();
                ResultSet tables = statement.executeQuery(
                        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()")) {
            return tables.next() && tables.getLong(1) == 0;
        }
    }

    public static void main(String[] args) {
        if (run(System.console(), args) != 0) System.exit(1);
    }

    private static int run(Console console, String[] args) {
        if (console == null || args.length != 1 || !isFictitiousSchema(args[0])) {
            System.err.println("Execute numa consola interativa e indique apenas uma base ficticia valida.");
            return 1;
        }

        char[] password = null;
        Properties properties = new Properties();
        try {
            console.printf("Verifique que a instancia indicada contem apenas dados ficticios.%n");
            String host = console.readLine("Host apresentado em Connect (sem https ou parametros): ");
            String portText = console.readLine("Porta apresentada em Connect (Enter para 4000): ");
            String username = console.readLine("Utilizador administrativo completo terminado em .root: ");
            if (host == null || portText == null || username == null) throw new IllegalArgumentException();
            int port = portText.isBlank() ? 4000 : Integer.parseInt(portText.trim());
            String url = jdbcUrl(host.trim(), port, args[0]);
            if (!isRootUser(username.trim())) throw new IllegalArgumentException();

            password = console.readPassword("Palavra-passe da base (nao sera mostrada): ");
            if (password == null || password.length == 0) throw new IllegalArgumentException();
            properties.setProperty("user", username.trim());
            // JDBC requires a String; it remains in process memory until collected.
            properties.setProperty("password", new String(password));
            DriverManager.setLoginTimeout(20);
            try (Connection connection = DriverManager.getConnection(url, properties)) {
                if (!inspect(connection, args[0])) {
                    console.printf("Ligacao estabelecida, mas a base ou a configuracao nao passou na verificacao.%n");
                    return 1;
                }
            }
            console.printf("Ligacao TLS verificada; base de ensaio sem tabelas visiveis e configuracao esperada nesta sessao.%n");
            console.printf("Isto nao confirma permissoes minimas, isolamento, migracoes ou restauro.%n");
            return 0;
        } catch (Exception ignored) {
            // JDBC exception messages can contain connection information.
            System.err.println("Nao foi possivel confirmar a ligacao. Nao foram alterados dados por este programa.");
            return 1;
        } finally {
            if (password != null) Arrays.fill(password, '\0');
            properties.remove("password");
        }
    }
}
