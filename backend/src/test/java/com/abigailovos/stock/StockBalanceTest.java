package com.abigailovos.stock;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class StockBalanceTest {
    @Test
    void addsAndSubtractsWithoutLosingPrecision() {
        assertThat(StockBalance.apply(new BigDecimal("2.50"), new BigDecimal("0.25")))
                .isEqualByComparingTo("2.75");
        assertThat(StockBalance.apply(new BigDecimal("2.50"), new BigDecimal("-2.50")))
                .isEqualByComparingTo("0");
    }

    @Test
    void rejectsInsufficientStock() {
        assertThatThrownBy(() -> StockBalance.apply(new BigDecimal("2"), new BigDecimal("-3")))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void rejectsZeroMovementAndInvalidStartingBalance() {
        assertThatThrownBy(() -> StockBalance.apply(BigDecimal.ZERO, BigDecimal.ZERO))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> StockBalance.apply(new BigDecimal("-1"), BigDecimal.ONE))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
