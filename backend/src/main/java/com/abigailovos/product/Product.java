package com.abigailovos.product;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "products")
public class Product {
    @Id
    @Column(length = 36, nullable = false, updatable = false)
    private String id;
    @Column(nullable = false, length = 150)
    private String name;
    @Column(nullable = false, length = 50)
    private String unit;
    @Column(nullable = false, precision = 19, scale = 2)
    private BigDecimal price;
    @Column(nullable = false)
    private boolean active = true;
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected Product() {
    }

    Product(String name, String unit, BigDecimal price) {
        this.id = UUID.randomUUID().toString();
        this.name = name.strip();
        this.unit = unit.strip();
        this.price = price;
        this.createdAt = Instant.now();
        this.updatedAt = this.createdAt;
    }

    public String getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public String getUnit() {
        return unit;
    }

    public BigDecimal getPrice() {
        return price;
    }

    /** Exact decimal representation for clients that cannot represent money in binary floating point. */
    public String getPriceText() {
        return price.toPlainString();
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public boolean isActive() { return active; }

    void update(String name, String unit, BigDecimal price) {
        this.name = name.strip();
        this.unit = unit.strip();
        this.price = price;
        this.updatedAt = Instant.now();
    }

    void setActive(boolean active) {
        this.active = active;
        this.updatedAt = Instant.now();
    }
}
