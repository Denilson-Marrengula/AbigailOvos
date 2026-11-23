package com.abigailovos.security;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.security.crypto.password.PasswordEncoder;
import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ErrorDispatchIntegrationTest {
    @LocalServerPort int port;
    @Autowired AppUserRepository users;
    @Autowired PasswordEncoder passwords;

    @Test void containerErrorDispatchPreservesStatusWithoutExposingDirectErrorPath() throws Exception {
        String username = "seller_" + UUID.randomUUID().toString().replace("-", "");
        String password = "test-password-123";
        users.saveAndFlush(new AppUser(username, passwords.encode(password), "SELLER"));
        String auth = Base64.getEncoder().encodeToString((username + ":" + password).getBytes(StandardCharsets.UTF_8));
        HttpClient client = HttpClient.newHttpClient();
        HttpRequest missing = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/api/products/" + UUID.randomUUID()))
                .header("Authorization", "Basic " + auth).GET().build();
        assertThat(client.send(missing, HttpResponse.BodyHandlers.ofString()).statusCode()).isEqualTo(404);
        HttpRequest error = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/error"))
                .header("Authorization", "Basic " + auth).GET().build();
        assertThat(client.send(error, HttpResponse.BodyHandlers.ofString()).statusCode()).isEqualTo(403);
    }
}
