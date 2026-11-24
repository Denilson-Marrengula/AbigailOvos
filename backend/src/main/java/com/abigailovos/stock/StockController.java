package com.abigailovos.stock;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.security.Principal;
import java.util.UUID;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/stock")
class StockController {
    private final StockService stock;
    StockController(StockService stock) { this.stock = stock; }

    record CreateMovement(@NotNull UUID operationId, @NotNull UUID productId, @NotNull StockMovement.Type type,
            @NotNull StockMovement.Direction direction,
            @NotNull @DecimalMin(value = "0.00", inclusive = false) @Digits(integer = 17, fraction = 2) BigDecimal quantity,
            @NotBlank @Size(max = 255) String reason) {}
    record Balance(UUID productId, BigDecimal quantity, BigDecimal reserved, BigDecimal available, String availableText) {}

    @PostMapping("/movements") @ResponseStatus(HttpStatus.CREATED)
    StockMovementEntity create(@Valid @RequestBody CreateMovement request, Principal principal) {
        if (request.type() == StockMovement.Type.SALE) throw new org.springframework.web.server.ResponseStatusException(HttpStatus.BAD_REQUEST);
        return stock.create(request.operationId(), request.productId(), request.type(), request.direction(),
                request.quantity(), request.reason(), principal.getName());
    }

    @GetMapping("/{productId}")
    @org.springframework.transaction.annotation.Transactional(readOnly = true, isolation = org.springframework.transaction.annotation.Isolation.REPEATABLE_READ)
    Balance balance(@PathVariable UUID productId, Authentication authentication) {
        boolean admin = authentication.getAuthorities().stream().anyMatch(a -> a.getAuthority().equals("ROLE_ADMIN"));
        BigDecimal quantity = stock.balance(productId, admin);
        BigDecimal reserved = stock.reserved(productId.toString());
        BigDecimal available = quantity.subtract(reserved);
        return new Balance(productId, quantity, reserved, available, available.toPlainString());
    }

    @GetMapping("/{productId}/movements")
    List<StockMovementEntity> history(@PathVariable UUID productId) { return stock.history(productId); }
}
