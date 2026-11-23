package com.abigailovos.sales;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.util.UUID;

@Entity
@Table(name = "sale_items")
public class SaleItem {
    @Id
    @Column(length = 36)
    private String id;
    @Column(name = "sale_id", nullable = false, length = 36)
    private String saleId;
    @Column(name = "product_id", nullable = false, length = 36)
    private String productId;
    @Column(name = "product_name", nullable = false, length = 150)
    private String productName;
    @Column(nullable = false, length = 50)
    private String unit;
    @Column(nullable = false, precision = 19, scale = 2)
    private BigDecimal quantity;
    @Column(name = "unit_price", nullable = false, precision = 19, scale = 2)
    private BigDecimal unitPrice;

    protected SaleItem() {
    }

    SaleItem(String saleId, com.abigailovos.product.Product product, BigDecimal quantity) {
        this.id = UUID.randomUUID().toString();
        this.saleId = saleId;
        this.productId = product.getId();
        this.productName = product.getName();
        this.unit = product.getUnit();
        this.quantity = quantity;
        this.unitPrice = product.getPrice();
    }

    public String getProductId() {
        return productId;
    }

    public String getProductName() {
        return productName;
    }

    public String getUnit() {
        return unit;
    }

    public BigDecimal getQuantity() {
        return quantity;
    }

    public BigDecimal getUnitPrice() {
        return unitPrice;
    }
}
