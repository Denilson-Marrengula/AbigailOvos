package com.abigailovos.stock;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/** A validated movement. Authorization and durable storage belong to the application layer. */
public record StockMovement(UUID id, UUID productId, UUID administratorId, Type type,
                            BigDecimal quantity, Direction direction, String reason, Instant occurredAt) {
    public enum Type { ENTRY, ADJUSTMENT, LOSS, BREAKAGE, SALE }
    public enum Direction { INCREASE, DECREASE }

    public StockMovement {
        Objects.requireNonNull(id, "id");
        Objects.requireNonNull(productId, "productId");
        Objects.requireNonNull(administratorId, "administratorId");
        Objects.requireNonNull(type, "type");
        Objects.requireNonNull(quantity, "quantity");
        Objects.requireNonNull(direction, "direction");
        Objects.requireNonNull(reason, "reason");
        Objects.requireNonNull(occurredAt, "occurredAt");
        if (quantity.signum() <= 0 || reason.isBlank()) {
            throw new IllegalArgumentException("A quantidade deve ser positiva e o motivo obrigatório");
        }
        if ((type == Type.ENTRY && direction != Direction.INCREASE)
                || ((type == Type.LOSS || type == Type.BREAKAGE || type == Type.SALE) && direction != Direction.DECREASE)) {
            throw new IllegalArgumentException("Direção inválida para o tipo de movimento");
        }
        reason = reason.strip();
    }

    public BigDecimal applyTo(BigDecimal balance) {
        return StockBalance.apply(balance, direction == Direction.INCREASE ? quantity : quantity.negate());
    }
}
