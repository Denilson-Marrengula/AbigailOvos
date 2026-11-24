package com.abigailovos.customer;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class CustomerPhoneTest {
    @Test void equivalentMozambiqueFormatsShareAKey() {
        for (String phone : new String[] {"84 123 4567", "+258 84 123 4567", "00258-84-123-4567", "258841234567"}) {
            assertThat(CustomerPhone.canonical(phone)).isEqualTo("+258841234567");
        }
        assertThat(CustomerPhone.canonical("+351 912 345 678")).isEqualTo("+351912345678");
        assertThat(CustomerPhone.canonical("21 123 456")).isEqualTo("+25821123456");
    }

    @Test void rejectsMissingAmbiguousAndMalformedNumbers() {
        for (String phone : new String[] {"", " ", "123", "+258", "00000000", "+258 1234567", "abc841234567",
                "84/123/4567", "+258+841234567", "+1234567890123456", "1".repeat(41)}) {
            assertThatThrownBy(() -> CustomerPhone.canonical(phone)).isInstanceOf(IllegalArgumentException.class);
        }
        assertThatThrownBy(() -> CustomerPhone.canonical(null)).isInstanceOf(IllegalArgumentException.class);
    }
}
