package com.abigailovos.security;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class TotpCodesTest {
    private static final byte[] RFC_SECRET = "12345678901234567890".getBytes(StandardCharsets.US_ASCII);

    @Test void matchesRfc6238Sha1Vectors() {
        long[] seconds = {59L, 1111111109L, 1111111111L, 1234567890L, 2000000000L, 20000000000L};
        String[] expected = {"94287082", "07081804", "14050471", "89005924", "69279037", "65353130"};
        for (int i = 0; i < seconds.length; i++) {
            assertThat(TotpCodes.generate(RFC_SECRET, seconds[i] / 30, 8)).isEqualTo(expected[i]);
        }
    }

    @Test void checksTheWindowAndRejectsPreviouslyConsumedSteps() {
        long step = 100_000;
        Instant now = Instant.ofEpochSecond(step * 30);
        String current = TotpCodes.generate(RFC_SECRET, step, 6);
        String previous = TotpCodes.generate(RFC_SECRET, step - 1, 6);
        String next = TotpCodes.generate(RFC_SECRET, step + 1, 6);
        assertThat(TotpCodes.matchingStep(RFC_SECRET, current, now, step - 1)).hasValue(step);
        assertThat(TotpCodes.matchingStep(RFC_SECRET, current, now, step)).isEmpty();
        assertThat(TotpCodes.matchingStep(RFC_SECRET, previous, now, step - 2)).hasValue(step - 1);
        assertThat(TotpCodes.matchingStep(RFC_SECRET, next, now, step)).hasValue(step + 1);
        assertThat(TotpCodes.matchingStep(RFC_SECRET, current, now.plusSeconds(60), -1)).isEmpty();
        assertThat(TotpCodes.matchingStep(RFC_SECRET, "12a456", now, -1)).isEmpty();
        assertThat(TotpCodes.matchingStep(RFC_SECRET, "12345", now, -1)).isEmpty();
        assertThat(TotpCodes.matchingStep(RFC_SECRET, null, now, -1)).isEmpty();
        assertThatThrownBy(() -> TotpCodes.generate(new byte[19], step, 6)).isInstanceOf(IllegalArgumentException.class);
    }
}
