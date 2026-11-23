package com.abigailovos.stock;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "stock_movements")
public class StockMovementEntity {
    @Id @Column(length = 36) private String id;
    @Column(name = "product_id", nullable = false, length = 36) private String productId;
    @Column(nullable = false, length = 150) private String administrator;
    @Enumerated(EnumType.STRING) @Column(name = "movement_type", nullable = false, length = 20)
    private StockMovement.Type type;
    @Enumerated(EnumType.STRING) @Column(nullable = false, length = 10)
    private StockMovement.Direction direction;
    @Column(nullable = false, precision = 19, scale = 2) private BigDecimal quantity;
    @Column(nullable = false, length = 255) private String reason;
    @Column(name = "occurred_at", nullable = false) private Instant occurredAt;

    protected StockMovementEntity() {}

    StockMovementEntity(StockMovement movement, String administrator) {
        id = movement.id().toString(); productId = movement.productId().toString();
        this.administrator = administrator; type = movement.type(); direction = movement.direction();
        quantity = movement.quantity(); reason = movement.reason(); occurredAt = movement.occurredAt();
    }

    public String getId() { return id; }
    public String getProductId() { return productId; }
    public String getAdministrator() { return administrator; }
    public StockMovement.Type getType() { return type; }
    public StockMovement.Direction getDirection() { return direction; }
    public BigDecimal getQuantity() { return quantity; }
    public String getReason() { return reason; }
    public Instant getOccurredAt() { return occurredAt; }
}
