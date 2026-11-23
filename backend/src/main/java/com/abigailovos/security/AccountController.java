package com.abigailovos.security;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
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

    AccountController(AppUserRepository users, PasswordEncoder passwords) {
        this.users = users;
        this.passwords = passwords;
    }

    record CreateSeller(@NotBlank @Size(min = 3, max = 100) @Pattern(regexp = "[a-zA-Z0-9._-]+") String username,
            @NotBlank @Size(min = 12, max = 72) @Pattern(regexp = "[\\x20-\\x7E]+") String password,
            @Size(max = 150) String displayName, @Size(max = 40) String phone) {
    }

    record Account(String id, String username, String role, boolean enabled, String displayName, String phone) {
        static Account from(AppUser u) { return new Account(u.getId(), u.getUsername(), u.getRole(), u.isEnabled(), u.getDisplayName(), u.getPhone()); }
    }

    record Session(String username, List<String> roles) {
    }

    record ChangeStatus(@NotNull Boolean enabled) {
    }

    record UpdateSeller(@NotBlank @Size(max = 150) String displayName, @Size(max = 40) String phone) {}

    @GetMapping("/me")
    Session me(Authentication auth) {
        return new Session(auth.getName(), auth.getAuthorities().stream().map(a -> a.getAuthority()).toList());
    }

    @PostMapping("/users")
    @ResponseStatus(HttpStatus.CREATED)
    Account createSeller(@Valid @RequestBody CreateSeller request) {
        if ((request.displayName() != null && request.displayName().isBlank())
                || (request.displayName() == null && request.phone() != null && !request.phone().isBlank())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Nome do vendedor obrigatório quando se indica contacto");
        }
        try {
            AppUser user = new AppUser(request.username(), passwords.encode(request.password()), "SELLER");
            if (request.displayName() != null) user.updateProfile(request.displayName(), request.phone());
            return Account.from(users.saveAndFlush(user));
        } catch (DataIntegrityViolationException ex) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Utilizador já existe");
        }
    }

    @GetMapping("/users")
    List<Account> list() {
        return users.findAll().stream().map(Account::from).toList();
    }

    @PatchMapping("/users/{id}/status")
    @Transactional
    Account changeStatus(@PathVariable String id, @Valid @RequestBody ChangeStatus request) {
        AppUser user = users.findById(id).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        if (!"SELLER".equals(user.getRole())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        }
        user.setEnabled(request.enabled());
        return Account.from(user);
    }

    @PutMapping("/users/{id}/profile")
    @Transactional
    Account updateSeller(@PathVariable String id, @Valid @RequestBody UpdateSeller request) {
        AppUser user = users.findById(id).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        if (!"SELLER".equals(user.getRole())) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        user.updateProfile(request.displayName(), request.phone());
        return Account.from(user);
    }
}
