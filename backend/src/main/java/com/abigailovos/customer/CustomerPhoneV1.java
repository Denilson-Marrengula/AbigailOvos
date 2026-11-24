package com.abigailovos.customer;

/** Frozen V12 canonicalization. Future policies must use a new version. */
public final class CustomerPhoneV1 {
    private CustomerPhoneV1() {}

    public static String canonical(String raw) {
        if (raw == null || raw.length() > 40) throw new IllegalArgumentException("Telefone inválido");
        String value = raw.strip();
        if (!value.matches("\\+?[0-9 ()-]+")) throw new IllegalArgumentException("Telefone inválido");
        String compact = value.replaceAll("[ ()-]", "");
        String digits;
        if (compact.startsWith("+")) {
            digits = compact.substring(1);
        } else if (compact.startsWith("00")) {
            digits = compact.substring(2);
        } else if (compact.startsWith("258") && (compact.length() == 11 || compact.length() == 12)) {
            digits = compact;
        } else if (compact.length() == 8 || compact.length() == 9) {
            digits = "258" + compact;
        } else {
            throw new IllegalArgumentException("Telefone inválido");
        }
        if (!digits.matches("[1-9][0-9]{7,14}")
                || (digits.startsWith("258") && digits.length() != 11 && digits.length() != 12)) {
            throw new IllegalArgumentException("Telefone inválido");
        }
        return "+" + digits;
    }
}
