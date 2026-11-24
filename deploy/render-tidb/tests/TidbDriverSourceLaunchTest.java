import java.sql.DriverManager;
import java.util.Arrays;
import java.util.Properties;

/** Verify source-file launcher driver discovery and TLS mode without connecting. */
public final class TidbDriverSourceLaunchTest {
    public static void main(String[] args) throws Exception {
        String url = "jdbc:mysql://example.tidbcloud.com:4000/abigailovos_tidb_test_12345678"
                + "?sslMode=VERIFY_IDENTITY&connectTimeout=15000&socketTimeout=30000";
        var properties = DriverManager.getDriver(url).getPropertyInfo(url, new Properties());
        if (Arrays.stream(properties).noneMatch(p -> p.name.equals("sslMode") && p.value.equals("VERIFY_IDENTITY"))) {
            throw new AssertionError("Modo TLS inesperado.");
        }
        System.out.println("Driver disponivel e modo TLS interpretado, sem ligacao de rede.");
    }
}
