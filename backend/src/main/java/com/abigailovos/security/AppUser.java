package com.abigailovos.security;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "app_users")
public class AppUser {
    @Id
    @Column(length = 36)
    private String id;
    @Column(nullable = false, unique = true, length = 100)
    private String username;
    @Column(name = "password_hash", nullable = false, length = 100)
    private String passwordHash;
    @Column(nullable = false, length = 20)
    private String role;
    @Column(nullable = false)
    private boolean enabled;
    @Column(name = "created_at", nullable = false)
    private Instant createdAt;
    @Column(name = "display_name", length = 150)
    private String displayName;
    @Column(length = 40)
    private String phone;

    protected AppUser() {
    }

    AppUser(String username, String hash, String role) {
        this.id = UUID.randomUUID().toString();
        this.username = username;
        this.passwordHash = hash;
        this.role = role;
        this.enabled = true;
        this.createdAt = Instant.now();
    }

    public String getId() {
        return id;
    }

    public String getUsername() {
        return username;
    }

    String getPasswordHash() {
        return passwordHash;
    }

    public String getRole() {
        return role;
    }

    public boolean isEnabled() {
        return enabled;
    }

    void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public String getDisplayName() { return displayName; }
    public String getPhone() { return phone; }
    void updateProfile(String displayName, String phone) {
        this.displayName = displayName.strip();
        this.phone = phone == null || phone.isBlank() ? null : phone.strip();
    }
}
