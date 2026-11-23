package com.abigailovos.stock;

import java.math.BigDecimal;
import java.util.Objects;

/** Pure balance calculation; persistence and concurrent updates are not yet implemented. */
public final class StockBalance {
    private StockBalance() {
    }

    public static BigDecimal apply(BigDecimal balance, BigDecimal change) {
        Objects.requireNonNull(balance, "balance");
        Objects.requireNonNull(change, "change");
        if (balance.signum() < 0 || change.signum() == 0) {
            throw new IllegalArgumentException("O saldo não pode ser negativo e o movimento não pode ser zero");
        }
        BigDecimal result = balance.add(change);
        if (result.signum() < 0) {
            throw new IllegalArgumentException("Stock insuficiente");
        }
        return result;
    }
}
