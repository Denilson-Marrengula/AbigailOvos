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
    @Column(name = "must_change_password", nullable = false)
    private boolean mustChangePassword;
    @Column(name = "temporary_password_expires_at")
    private Instant temporaryPasswordExpiresAt;
    @Column(name = "session_epoch", nullable = false)
    private long sessionEpoch;

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
        if (this.enabled != enabled) invalidateSessions();
        this.enabled = enabled;
    }

    boolean mustChangePassword() { return mustChangePassword; }
    Instant temporaryPasswordExpiresAt() { return temporaryPasswordExpiresAt; }
    long sessionEpoch() { return sessionEpoch; }

    void invalidateSessions() {
        if (sessionEpoch == Long.MAX_VALUE) throw new IllegalStateException("Não foi possível revogar as sessões.");
        sessionEpoch++;
    }

    void setTemporaryPassword(String hash, Instant expiresAt) {
        invalidateSessions();
        this.passwordHash = hash;
        this.mustChangePassword = true;
        this.temporaryPasswordExpiresAt = expiresAt;
    }

    void changePassword(String hash) {
        invalidateSessions();
        this.passwordHash = hash;
        this.mustChangePassword = false;
        this.temporaryPasswordExpiresAt = null;
    }

    public String getDisplayName() { return displayName; }
    public String getPhone() { return phone; }
    void updateProfile(String displayName, String phone) {
        this.displayName = displayName.strip();
        this.phone = phone == null || phone.isBlank() ? null : phone.strip();
    }
}
