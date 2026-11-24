package com.abigailovos.security;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** AES-GCM envelope for a TOTP secret. Key provisioning and rotation are not implemented here. */
final class MfaSecretCipher {
    private static final byte VERSION = 1;
    private static final int NONCE_BYTES = 12;
    private static final int TAG_BYTES = 16;
    private MfaSecretCipher() {}

    static byte[] encrypt(byte[] key, String accountId, byte[] secret, SecureRandom random) {
        validateKeyAndAccount(key, accountId);
        if (secret == null || secret.length < 20 || secret.length > 64 || random == null) {
            throw new IllegalArgumentException("Segredo de autenticador inválido");
        }
        byte[] nonce = new byte[NONCE_BYTES];
        random.nextBytes(nonce);
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(TAG_BYTES * 8, nonce));
            cipher.updateAAD(accountId.getBytes(StandardCharsets.UTF_8));
            byte[] encrypted = cipher.doFinal(secret);
            byte[] result = new byte[1 + NONCE_BYTES + encrypted.length];
            result[0] = VERSION;
            System.arraycopy(nonce, 0, result, 1, NONCE_BYTES);
            System.arraycopy(encrypted, 0, result, 1 + NONCE_BYTES, encrypted.length);
            return result;
        } catch (GeneralSecurityException error) {
            throw new IllegalStateException("Não foi possível proteger o autenticador.");
        }
    }

    static byte[] decrypt(byte[] key, String accountId, byte[] envelope) {
        validateKeyAndAccount(key, accountId);
        if (envelope == null || envelope.length < 1 + NONCE_BYTES + TAG_BYTES + 20
                || envelope.length > 1 + NONCE_BYTES + TAG_BYTES + 64 || envelope[0] != VERSION) {
            throw new IllegalArgumentException("Registo de autenticador inválido");
        }
        byte[] nonce = Arrays.copyOfRange(envelope, 1, 1 + NONCE_BYTES);
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(TAG_BYTES * 8, nonce));
            cipher.updateAAD(accountId.getBytes(StandardCharsets.UTF_8));
            return cipher.doFinal(envelope, 1 + NONCE_BYTES, envelope.length - 1 - NONCE_BYTES);
        } catch (GeneralSecurityException error) {
            // No key, account identifier, ciphertext or cryptographic details in the exception.
            throw new IllegalStateException("Não foi possível abrir o autenticador.");
        }
    }

    private static void validateKeyAndAccount(byte[] key, String accountId) {
        if (key == null || key.length != 32 || accountId == null || accountId.isBlank() || accountId.length() > 36) {
            throw new IllegalArgumentException("Configuração do autenticador inválida");
        }
    }
}
