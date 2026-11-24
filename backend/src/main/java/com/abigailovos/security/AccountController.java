package com.abigailovos.security;

import jakarta.validation.Valid;
import com.abigailovos.audit.AuditLog;
import java.security.Principal;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Clock;
import java.time.Instant;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.Base64;
import java.util.Map;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api")
class AccountController {
    private final AppUserRepository users;
    private final PasswordEncoder passwords;
    private final AuditLog audit;
    private final UsernameReservations reservations;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();

    AccountController(AppUserRepository users, PasswordEncoder passwords, AuditLog audit, UsernameReservations reservations, Clock clock) {
        this.users = users;
        this.passwords = passwords;
        this.audit = audit;
        this.reservations = reservations;
        this.clock = clock;
    }

    record CreateSeller(@NotBlank @Size(min = 3, max = 100) @Pattern(regexp = "[a-zA-Z0-9._-]+") String username,
            @NotBlank @Size(min = 12, max = 72) @Pattern(regexp = "[\\x20-\\x7E]+") String password,
            @Size(max = 150) String displayName, @Size(max = 40) String phone) {
        @Override public String toString() { return "CreateSeller[redacted]"; }
    }

    record Account(String id, String username, String role, boolean enabled, String displayName, String phone) {
        static Account from(AppUser u) { return new Account(u.getId(), u.getUsername(), u.getRole(), u.isEnabled(), u.getDisplayName(), u.getPhone()); }
    }

    record Session(String username, List<String> roles, boolean mustChangePassword) {
    }

    record ChangeStatus(@NotNull Boolean enabled) {
    }

    record UpdateSeller(@NotBlank @Size(max = 150) String displayName, @Size(max = 40) String phone) {}

    record ChangePassword(@NotBlank @Size(max = 72) String currentPassword,
            @NotBlank @Size(min = 12, max = 72) @Pattern(regexp = "[\\x20-\\x7E]+") String newPassword) {
        @Override public String toString() { return "ChangePassword[redacted]"; }
    }

    record TemporaryPassword(String temporaryPassword, Instant expiresAt) {
        @Override public String toString() { return "TemporaryPassword[redacted]"; }
    }

    @GetMapping("/me")
    Session me(Authentication auth) {
        boolean mustChange = (auth.getPrincipal() instanceof AccountPrincipal account && account.mustChangePassword())
                || (auth.getPrincipal() instanceof SessionPrincipal session && session.mustChangePassword());
        return new Session(auth.getName(), auth.getAuthorities().stream().map(a -> a.getAuthority()).toList(), mustChange);
    }

    @PutMapping("/account/password")
    @Transactional
    ResponseEntity<Map<String, Boolean>> changePassword(@Valid @RequestBody ChangePassword request, Authentication auth) {
        AppUser snapshot = users.findByUsername(auth.getName())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED));
        AppUser user = users.findForUpdate(snapshot.getId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED));
        if (!user.isEnabled() || !user.getUsername().equals(auth.getName())
                || (user.mustChangePassword() && (user.temporaryPasswordExpiresAt() == null
                        || !user.temporaryPasswordExpiresAt().isAfter(clock.instant())))
                || !passwords.matches(request.currentPassword(), user.getPasswordHash())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED);
        }
        if (passwords.matches(request.newPassword(), user.getPasswordHash()))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "A nova palavra-passe tem de ser diferente");
        user.changePassword(passwords.encode(request.newPassword()));
        audit.record(auth.getName(), "PASSWORD_CHANGED", "USER", user.getId(), "source=SELF");
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(Map.of("changed", true));
    }

    @PatchMapping("/users/{id}/password-reset")
    @Transactional
    ResponseEntity<TemporaryPassword> resetSellerPassword(@PathVariable String id, Principal principal) {
        AppUser user = users.findForUpdate(id).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        if (!"SELLER".equals(user.getRole())) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        if (!user.isEnabled()) throw new ResponseStatusException(HttpStatus.CONFLICT, "A conta está desativada");
        byte[] bytes = new byte[24];
        random.nextBytes(bytes);
        String temporary = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Instant expiresAt = clock.instant().plus(Duration.ofHours(24));
        user.setTemporaryPassword(passwords.encode(temporary), expiresAt);
        audit.record(principal.getName(), "SELLER_PASSWORD_RESET", "USER", user.getId(), "temporary=true");
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new TemporaryPassword(temporary, expiresAt));
    }

    @PostMapping("/users")
    @ResponseStatus(HttpStatus.CREATED)
    @Transactional
    Account createSeller(@Valid @RequestBody CreateSeller request, Principal principal) {
        if ((request.displayName() != null && request.displayName().isBlank())
                || (request.displayName() == null && request.phone() != null && !request.phone().isBlank())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Nome do vendedor obrigatório quando se indica contacto");
        }
        AppUser user = new AppUser(request.username(), passwords.encode(request.password()), "SELLER");
        // A password chosen by an administrator is temporary, including on first access.
        user.setTemporaryPassword(user.getPasswordHash(), clock.instant().plus(Duration.ofHours(24)));
        try {
            if (request.displayName() != null) user.updateProfile(request.displayName(), request.phone());
            reservations.reserve(user);
            users.saveAndFlush(user);
        } catch (DataIntegrityViolationException ex) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Utilizador já existe");
        }
        audit.record(principal.getName(), "SELLER_CREATED", "USER", user.getId(), "role=SELLER");
        return Account.from(user);
    }

    @DeleteMapping("/users/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Transactional
    void deleteSeller(@PathVariable String id, Principal principal) {
        AppUser user = users.findForUpdate(id).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        if (!"SELLER".equals(user.getRole())) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        if (!reservations.belongsTo(user))
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Reserva de utilizador inconsistente");
        users.delete(user);
        audit.record(principal.getName(), "SELLER_DELETED", "USER", id, "history=retained");
        users.flush();
    }

    @GetMapping("/users")
    List<Account> list() {
        return users.findAll().stream().map(Account::from).toList();
    }

    @PatchMapping("/users/{id}/status")
    @Transactional
    Account changeStatus(@PathVariable String id, @Valid @RequestBody ChangeStatus request, Principal principal) {
        AppUser user = users.findForUpdate(id).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        if (!"SELLER".equals(user.getRole())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        }
        user.setEnabled(request.enabled());
        audit.record(principal.getName(), "SELLER_STATUS_SET", "USER", user.getId(), "enabled=" + request.enabled());
        return Account.from(user);
    }

    @PutMapping("/users/{id}/profile")
    @Transactional
    Account updateSeller(@PathVariable String id, @Valid @RequestBody UpdateSeller request, Principal principal) {
        AppUser user = users.findForUpdate(id).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        if (!"SELLER".equals(user.getRole())) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        user.updateProfile(request.displayName(), request.phone());
        audit.record(principal.getName(), "SELLER_PROFILE_UPDATED", "USER", user.getId(), "fields=displayName,phone");
        return Account.from(user);
    }
}
