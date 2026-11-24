package com.abigailovos.sales;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.Instant;

@Entity
@Table(name = "sales")
public class Sale {
    public enum Delivery {
        PENDING, DELIVERED, CANCELLED
    }

    public enum Payment {
        PENDING, PAID
    }

    public enum PaymentMethod {
        EMOLA, MPESA, BANK, CASH
    }

    @Id
    @Column(length = 36)
    private String id;
    @Column(name = "request_hash", nullable = false, length = 64)
    private String requestHash;
    @Column(name = "customer_id", nullable = false, length = 36)
    private String customerId;
    @Column(nullable = false, length = 150)
    private String seller;
    @Enumerated(EnumType.STRING)
    @Column(name = "delivery_status", nullable = false, length = 20)
    private Delivery deliveryStatus;
    @Enumerated(EnumType.STRING)
    @Column(name = "payment_status", nullable = false, length = 20)
    private Payment paymentStatus;
    @Enumerated(EnumType.STRING)
    @Column(name = "payment_method", length = 20)
    private PaymentMethod paymentMethod;
    @Column(nullable = false, precision = 19, scale = 2)
    private BigDecimal total;
    @Column(name = "created_at", nullable = false)
    private Instant createdAt;
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;
    @Column(name = "updated_by", nullable = false, length = 150)
    private String updatedBy;
    // Historical rows intentionally keep null when the actual event time is unknown.
    @Column(name = "delivered_at")
    private Instant deliveredAt;
    @Column(name = "paid_at")
    private Instant paidAt;
    @Column(name = "cancelled_at")
    private Instant cancelledAt;

    protected Sale() {
    }

    Sale(String id, String hash, String customerId, String seller, Delivery delivery, Payment payment,
            BigDecimal total, PaymentMethod paymentMethod) {
        this.id = id;
        this.requestHash = hash;
        this.customerId = customerId;
        this.seller = seller;
        this.deliveryStatus = delivery;
        this.paymentStatus = payment;
        this.paymentMethod = paymentMethod;
        this.total = total;
        this.createdAt = Instant.now();
        this.updatedAt = createdAt;
        this.updatedBy = seller;
        this.deliveredAt = delivery == Delivery.DELIVERED ? createdAt : null;
        this.paidAt = payment == Payment.PAID ? createdAt : null;
        this.cancelledAt = delivery == Delivery.CANCELLED ? createdAt : null;
    }

    public String getId() {
        return id;
    }

    public String getRequestHash() {
        return requestHash;
    }

    public String getCustomerId() {
        return customerId;
    }

    public String getSeller() {
        return seller;
    }

    public Delivery getDeliveryStatus() {
        return deliveryStatus;
    }

    public Payment getPaymentStatus() {
        return paymentStatus;
    }

    public PaymentMethod getPaymentMethod() {
        return paymentMethod;
    }

    public BigDecimal getTotal() {
        return total;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getDeliveredAt() {
        return deliveredAt;
    }

    public Instant getPaidAt() {
        return paidAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public String getUpdatedBy() {
        return updatedBy;
    }

    void changeDelivery(Delivery value, String actor) {
        deliveryStatus = value;
        touch(actor);
        if (value == Delivery.DELIVERED) deliveredAt = updatedAt;
        if (value == Delivery.CANCELLED) cancelledAt = updatedAt;
    }

    void paid(String actor, PaymentMethod method) {
        paymentStatus = Payment.PAID;
        paymentMethod = method;
        touch(actor);
        paidAt = updatedAt;
    }

    private void touch(String actor) {
        updatedAt = Instant.now();
        updatedBy = actor;
    }
}
