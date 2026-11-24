package com.abigailovos.security;

import java.security.SecureRandom;
import java.util.Arrays;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class MfaSecretCipherTest {
    @Test void encryptsAndBindsTheSecretToTheAccount() {
        byte[] key = new byte[32];
        byte[] secret = new byte[20];
        var random = new SecureRandom();
        random.nextBytes(key);
        random.nextBytes(secret);
        String account = "12345678-1234-1234-1234-123456789abc";
        byte[] first = MfaSecretCipher.encrypt(key, account, secret, random);
        byte[] second = MfaSecretCipher.encrypt(key, account, secret, random);
        assertThat(first).isNotEqualTo(secret).isNotEqualTo(second);
        assertThat(MfaSecretCipher.decrypt(key, account, first)).isEqualTo(secret);
        assertThatThrownBy(() -> MfaSecretCipher.decrypt(key, "other-account", first))
                .isInstanceOf(IllegalStateException.class).hasMessage("Não foi possível abrir o autenticador.");
        byte[] modified = first.clone();
        modified[modified.length - 1] ^= 1;
        assertThatThrownBy(() -> MfaSecretCipher.decrypt(key, account, modified)).isInstanceOf(IllegalStateException.class);
        byte[] differentKey = key.clone();
        differentKey[0] ^= 1;
        assertThatThrownBy(() -> MfaSecretCipher.decrypt(differentKey, account, first)).isInstanceOf(IllegalStateException.class);
        byte[] invalidVersion = first.clone();
        invalidVersion[0] = 2;
        assertThatThrownBy(() -> MfaSecretCipher.decrypt(key, account, invalidVersion)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> MfaSecretCipher.decrypt(key, account, Arrays.copyOf(first, 10))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> MfaSecretCipher.encrypt(new byte[16], account, secret, random)).isInstanceOf(IllegalArgumentException.class);
    }
}
