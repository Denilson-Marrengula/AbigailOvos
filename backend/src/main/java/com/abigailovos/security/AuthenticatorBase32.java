package com.abigailovos.security;

/** RFC 4648 unpadded Base32 for manual entry into authenticator applications. */
final class AuthenticatorBase32 {
    private static final char[] ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".toCharArray();
    private AuthenticatorBase32() {}

    static String encode(byte[] bytes) {
        if (bytes == null) throw new IllegalArgumentException("Segredo inválido");
        StringBuilder output = new StringBuilder((bytes.length * 8 + 4) / 5);
        int buffer = 0;
        int bits = 0;
        for (byte value : bytes) {
            buffer = (buffer << 8) | (value & 0xff);
            bits += 8;
            while (bits >= 5) {
                bits -= 5;
                output.append(ALPHABET[(buffer >>> bits) & 31]);
            }
        }
        if (bits > 0) output.append(ALPHABET[(buffer << (5 - bits)) & 31]);
        return output.toString();
    }
}
