package com.abigailovos.customer;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import com.fasterxml.jackson.annotation.JsonIgnore;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "customers")
public class Customer {
    @Id
    @Column(length = 36, nullable = false, updatable = false)
    private String id;
    @Column(nullable = false, length = 150)
    private String name;
    @Column(length = 40)
    private String phone;
    @JsonIgnore
    @Column(name = "phone_key", nullable = false, length = 16, unique = true)
    private String phoneKey;
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected Customer() {
    }

    public Customer(String name, String phone) {
        this.id = UUID.randomUUID().toString();
        this.name = name.strip();
        this.phoneKey = CustomerPhone.canonical(phone);
        this.phone = phone.strip();
        this.createdAt = Instant.now();
        this.updatedAt = createdAt;
    }

    public String getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public String getPhone() {
        return phone;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    void update(String name, String phone) {
        this.name = name.strip();
        this.phoneKey = CustomerPhone.canonical(phone);
        this.phone = phone.strip();
        this.updatedAt = Instant.now();
    }
}
