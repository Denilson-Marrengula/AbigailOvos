package com.abigailovos.security;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Locale;
import java.util.OptionalLong;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/** RFC 6238 primitives only. Login enforcement and atomic replay prevention are separate. */
final class TotpCodes {
    private static final long STEP_SECONDS = 30;
    private TotpCodes() {}

    static String generate(byte[] secret, long step, int digits) {
        if (secret == null || secret.length < 20 || step < 0 || (digits != 6 && digits != 8)) {
            throw new IllegalArgumentException("Parâmetros do autenticador inválidos");
        }
        try {
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(new SecretKeySpec(secret, "HmacSHA1"));
            byte[] digest = mac.doFinal(ByteBuffer.allocate(Long.BYTES).putLong(step).array());
            int offset = digest[digest.length - 1] & 0x0f;
            int binary = ((digest[offset] & 0x7f) << 24)
                    | ((digest[offset + 1] & 0xff) << 16)
                    | ((digest[offset + 2] & 0xff) << 8)
                    | (digest[offset + 3] & 0xff);
            int modulus = digits == 6 ? 1_000_000 : 100_000_000;
            return String.format(Locale.ROOT, "%0" + digits + "d", binary % modulus);
        } catch (GeneralSecurityException error) {
            throw new IllegalStateException("Não foi possível verificar o autenticador.");
        }
    }

    /**
     * Returns the newest matching time step within one step of the server clock.
     * The caller must compare and persist the returned step atomically under a
     * database lock. This method alone does not prevent concurrent replay.
     */
    static OptionalLong matchingStep(byte[] secret, String code, Instant now, long lastAcceptedStep) {
        if (secret == null || secret.length < 20 || now == null || now.getEpochSecond() < 0) {
            throw new IllegalArgumentException("Parâmetros do autenticador inválidos");
        }
        if (code == null || !code.matches("[0-9]{6}")) return OptionalLong.empty();
        long current = now.getEpochSecond() / STEP_SECONDS;
        byte[] supplied = code.getBytes(StandardCharsets.US_ASCII);
        long accepted = -1;
        for (int offset = -1; offset <= 1; offset++) {
            long candidate = current + offset;
            if (candidate < 0) continue;
            byte[] expected = generate(secret, candidate, 6).getBytes(StandardCharsets.US_ASCII);
            if (MessageDigest.isEqual(supplied, expected) && candidate > lastAcceptedStep) accepted = candidate;
        }
        return accepted < 0 ? OptionalLong.empty() : OptionalLong.of(accepted);
    }
}
