package com.abigailovos.product;

import com.abigailovos.audit.AuditLog;
import java.security.Principal;
import java.math.BigDecimal;
import java.net.URI;
import java.util.List;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@RestController
@RequestMapping("/api/products")
class ProductController {
    private final ProductRepository products;
    private final AuditLog audit;

    ProductController(ProductRepository products, AuditLog audit) {
        this.products = products;
        this.audit = audit;
    }

    record CreateProduct(@NotBlank @Size(max = 150) String name,
            @NotBlank @Size(max = 50) String unit,
            @NotNull @DecimalMin("0.00") @Digits(integer = 17, fraction = 2) BigDecimal price) {
    }

    record ChangeStatus(@NotNull Boolean active) {}
    record MinimumStock(@NotNull @DecimalMin("0.00") @Digits(integer = 17, fraction = 2)
            BigDecimal minimumStock) {}

    @PostMapping
    @Transactional
    ResponseEntity<Product> create(@Valid @RequestBody CreateProduct request, Principal principal) {
        Product product = products.save(new Product(request.name(), request.unit(), request.price()));
        audit.record(principal.getName(), "PRODUCT_CREATED", "PRODUCT", product.getId(), "active=true");
        return ResponseEntity.created(URI.create("/api/products/" + product.getId())).body(product);
    }

    @GetMapping
    List<Product> list(Authentication authentication) {
        return isAdmin(authentication) ? products.findAll() : products.findByActiveTrue();
    }

    @GetMapping("/{id}")
    Product get(@PathVariable String id, Authentication authentication) {
        Product product = find(id);
        if (!product.isActive() && !isAdmin(authentication)) throw new ResponseStatusException(NOT_FOUND);
        return product;
    }

    @PutMapping("/{id}")
    @Transactional
    Product update(@PathVariable String id, @Valid @RequestBody CreateProduct request, Authentication principal) {
        Product product = findForUpdate(id);
        if (!product.isActive() && !isAdmin(principal)) throw new ResponseStatusException(NOT_FOUND);
        product.update(request.name(), request.unit(), request.price());
        audit.record(principal.getName(), "PRODUCT_UPDATED", "PRODUCT", product.getId(), "fields=name,unit,price");
        return product;
    }

    @PatchMapping("/{id}/status")
    @Transactional
    Product changeStatus(@PathVariable String id, @Valid @RequestBody ChangeStatus request, Principal principal) {
        Product product = findForUpdate(id);
        product.setActive(request.active());
        audit.record(principal.getName(), "PRODUCT_STATUS_SET", "PRODUCT", product.getId(), "active=" + request.active());
        return product;
    }

    @PutMapping("/{id}/minimum-stock")
    @Transactional
    Product setMinimumStock(@PathVariable String id, @Valid @RequestBody MinimumStock request, Authentication principal) {
        Product product = findForUpdate(id);
        if (!product.isActive() && !isAdmin(principal)) throw new ResponseStatusException(NOT_FOUND);
        product.setMinimumStock(request.minimumStock());
        audit.record(principal.getName(), "PRODUCT_MINIMUM_STOCK_SET", "PRODUCT", product.getId(), "configured=true");
        return product;
    }

    @DeleteMapping("/{id}/minimum-stock")
    @Transactional
    Product clearMinimumStock(@PathVariable String id, Authentication principal) {
        Product product = findForUpdate(id);
        if (!product.isActive() && !isAdmin(principal)) throw new ResponseStatusException(NOT_FOUND);
        product.setMinimumStock(null);
        audit.record(principal.getName(), "PRODUCT_MINIMUM_STOCK_SET", "PRODUCT", product.getId(), "configured=false");
        return product;
    }

    private Product find(String id) {
        return products.findById(id).orElseThrow(() -> new ResponseStatusException(NOT_FOUND));
    }

    private Product findForUpdate(String id) {
        return products.findForUpdate(id).orElseThrow(() -> new ResponseStatusException(NOT_FOUND));
    }

    private boolean isAdmin(Authentication auth) {
        return auth.getAuthorities().stream().anyMatch(a -> a.getAuthority().equals("ROLE_ADMIN"));
    }
}
