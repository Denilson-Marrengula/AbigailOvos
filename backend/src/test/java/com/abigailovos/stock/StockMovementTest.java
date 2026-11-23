package com.abigailovos.stock;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import static com.abigailovos.stock.StockMovement.Direction.*;
import static com.abigailovos.stock.StockMovement.Type.*;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class StockMovementTest {
    private StockMovement movement(StockMovement.Type type, StockMovement.Direction direction,
                                   String quantity, String reason) {
        return new StockMovement(UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), type,
                new BigDecimal(quantity), direction, reason, Instant.parse("2026-01-01T00:00:00Z"));
    }

    @Test
    void appliesEntriesAndBothAdjustmentDirections() {
        assertThat(movement(ENTRY, INCREASE, "3", "Compra").applyTo(BigDecimal.TEN))
                .isEqualByComparingTo("13");
        assertThat(movement(ADJUSTMENT, INCREASE, "1", "Contagem").applyTo(BigDecimal.TEN))
                .isEqualByComparingTo("11");
        assertThat(movement(ADJUSTMENT, DECREASE, "1", "Contagem").applyTo(BigDecimal.TEN))
                .isEqualByComparingTo("9");
    }

    @Test
    void appliesLossAndBreakageAndRejectsInsufficientBalance() {
        for (var type : new StockMovement.Type[] { LOSS, BREAKAGE, ADJUSTMENT }) {
            var movement = movement(type, DECREASE, "3", "Motivo");
            assertThat(movement.applyTo(new BigDecimal("3"))).isEqualByComparingTo("0");
            assertThatThrownBy(() -> movement.applyTo(new BigDecimal("2")))
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }

    @Test
    void rejectsInvalidDirectionsAndQuantitiesAndBlankReasons() {
        assertThatThrownBy(() -> movement(ENTRY, DECREASE, "1", "Motivo"))
                .isInstanceOf(IllegalArgumentException.class);
        for (var type : new StockMovement.Type[] { LOSS, BREAKAGE }) {
            assertThatThrownBy(() -> movement(type, INCREASE, "1", "Motivo"))
                    .isInstanceOf(IllegalArgumentException.class);
        }
        for (var quantity : new String[] { "0", "-1" }) {
            assertThatThrownBy(() -> movement(ENTRY, INCREASE, quantity, "Motivo"))
                    .isInstanceOf(IllegalArgumentException.class);
        }
        assertThatThrownBy(() -> movement(ENTRY, INCREASE, "1", "  "))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void keepsAuditFieldsAndNormalizesReason() {
        var id = UUID.randomUUID();
        var product = UUID.randomUUID();
        var administrator = UUID.randomUUID();
        var date = Instant.parse("2026-01-01T00:00:00Z");
        var movement = new StockMovement(id, product, administrator, ENTRY, BigDecimal.ONE,
                INCREASE, "  Receção  ", date);
        assertThat(movement.id()).isEqualTo(id);
        assertThat(movement.productId()).isEqualTo(product);
        assertThat(movement.administratorId()).isEqualTo(administrator);
        assertThat(movement.occurredAt()).isEqualTo(date);
        assertThat(movement.reason()).isEqualTo("Receção");
    }
}
