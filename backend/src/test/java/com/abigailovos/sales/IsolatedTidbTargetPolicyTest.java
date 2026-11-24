package com.abigailovos.sales;

import java.util.List;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Unit checks for the opt-in test target policy; does not open a connection. */
class IsolatedTidbTargetPolicyTest {
    private static final String SAFE = "jdbc:mysql://example.tidbcloud.com:4000/abigailovos_tidb_test_1234abcd?sslMode=VERIFY_IDENTITY";

    @Test void acceptsOnlyTheExplicitTestSchemaAndRedactsCredentials() {
        var target = IsolatedTidbCompatibilityTest.validatedTarget(SAFE, "test-user", "test-secret");
        assertThat(target.schema()).isEqualTo("abigailovos_tidb_test_1234abcd");
        assertThat(target.toString()).doesNotContain("test-user", "test-secret");
    }

    @Test void rejectsInsecureAmbiguousOrNonTestTargetsBeforeConnecting() {
        for (String url : List.of(
                SAFE.replace("abigailovos_tidb_test_1234abcd", "production"),
                SAFE.replace("abigailovos_tidb_test_1234abcd", "abigailovos_tidb_test_short"),
                SAFE.replace("sslMode=VERIFY_IDENTITY", "sslMode=DISABLED"),
                SAFE.replace("sslMode=VERIFY_IDENTITY", "sslMode=VERIFY_CA"),
                SAFE + "&useSSL=false",
                SAFE.replace("example.tidbcloud.com", "localhost"),
                SAFE.replace("example.tidbcloud.com", "tidbcloud.com.attacker.example"),
                SAFE.replace("example.tidbcloud.com", "user:password@example.tidbcloud.com"),
                SAFE.replace(":4000/", "/"))) {
            assertThatThrownBy(() -> IsolatedTidbCompatibilityTest.validatedTarget(url, "test-user", "test-secret"))
                    .isInstanceOf(IllegalStateException.class);
        }
        assertThatThrownBy(() -> IsolatedTidbCompatibilityTest.validatedTarget(null, "test-user", "test-secret"))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> IsolatedTidbCompatibilityTest.validatedTarget(SAFE, "", "test-secret"))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> IsolatedTidbCompatibilityTest.validatedTarget(SAFE, "test-user", ""))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test void rejectsTheSchemaReservedForTheRealPilotBeforeConnecting() {
        String reserved = "abigailovos_tidb_test_4292b79106cb4fac";
        for (String host : List.of("example.tidbcloud.com", "other.tidbcloud.com")) {
            String url = SAFE.replace("example.tidbcloud.com", host)
                    .replace("abigailovos_tidb_test_1234abcd", reserved);
            assertThatThrownBy(() -> IsolatedTidbCompatibilityTest.validatedTarget(url, "test-user", "test-secret"))
                    .isInstanceOf(IllegalStateException.class);
        }
    }

    @Test void rejectsRootAccountsBeforeConnecting() {
        for (String root : List.of("root", "ROOT", "Prefix123.root", " Prefix123.ROOT ")) {
            assertThatThrownBy(() -> IsolatedTidbCompatibilityTest.validatedTarget(SAFE, root, "test-secret"))
                    .isInstanceOf(IllegalStateException.class);
        }
    }
}
