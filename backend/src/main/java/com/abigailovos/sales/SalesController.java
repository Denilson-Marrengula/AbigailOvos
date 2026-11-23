package com.abigailovos.sales;

import com.abigailovos.customer.Customer;
import com.abigailovos.product.Product;
import com.abigailovos.stock.StockService;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.security.MessageDigest;
import java.security.Principal;
import java.time.Instant;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/sales")
class SalesController {
    private final EntityManager em;
    private final StockService stock;
    private final ObjectMapper json;

    SalesController(EntityManager em, StockService stock, ObjectMapper json) {
        this.em = em;
        this.stock = stock;
        this.json = json;
    }

    record NewCustomer(@NotBlank @Size(max = 150) String name, @Size(max = 40) String phone) {
    }

    record Item(@NotNull UUID productId,
            @NotNull @DecimalMin(value = "0", inclusive = false) @Digits(integer = 17, fraction = 2) BigDecimal quantity,
            @NotNull @DecimalMin("0") @Digits(integer = 17, fraction = 2) BigDecimal expectedUnitPrice) {
    }

    record Create(@NotNull UUID id, UUID customerId, @Valid NewCustomer customer,
            @NotEmpty @Size(max = 100) List<@NotNull @Valid Item> items,
            @NotNull Boolean deliverNow, @NotNull Boolean paid) {
    }

    record View(String id, String customerId, String customerName, String seller, Sale.Delivery deliveryStatus,
            Sale.Payment paymentStatus, BigDecimal total, String totalText, Instant createdAt, List<SaleItem> items) {
    }

    private View view(Sale sale) {
        Customer customer = em.find(Customer.class, sale.getCustomerId());
        List<SaleItem> items = em
                .createQuery("select i from SaleItem i where i.saleId = :id order by i.productName", SaleItem.class)
                .setParameter("id", sale.getId()).getResultList();
        return new View(sale.getId(), sale.getCustomerId(), customer.getName(), sale.getSeller(),
                sale.getDeliveryStatus(),
                sale.getPaymentStatus(), sale.getTotal(), sale.getTotal().toPlainString(), sale.getCreatedAt(), items);
    }

    @GetMapping
    @Transactional(readOnly = true)
    List<View> list() {
        return em.createQuery("select s from Sale s order by s.createdAt desc", Sale.class).getResultList().stream()
                .map(this::view).toList();
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @Transactional(isolation = Isolation.READ_COMMITTED)
    View create(@Valid @RequestBody Create request, Principal principal) throws Exception {
        if ((request.customerId() == null) == (request.customer() == null))
            throw bad("Escolha um cliente existente ou registe um novo.");
        String id = request.id().toString();
        String hash = HexFormat.of()
                .formatHex(MessageDigest.getInstance("SHA-256").digest(json.writeValueAsBytes(request)));
        Sale existing = em.find(Sale.class, id);
        if (existing != null) return existingSale(existing, principal, hash);
        Map<String, BigDecimal> quantities = new TreeMap<>();
        for (Item item : request.items()) {
            if (quantities.putIfAbsent(item.productId().toString(), item.quantity()) != null)
                throw bad("Produto repetido");
        }
        Map<String, Product> products = new LinkedHashMap<>();
        for (String productId : quantities.keySet()) {
            Product product = stock.lockProduct(productId);
            products.put(productId, product);
        }
        // A concurrent request with the same id may have committed while this one waited for product locks.
        existing = em.find(Sale.class, id);
        if (existing != null) return existingSale(existing, principal, hash);
        for (Product product : products.values()) {
            if (!product.isActive()) throw bad("Produto inativo");
        }
        for (String productId : quantities.keySet()) {
            if (stock.available(productId).compareTo(quantities.get(productId)) < 0)
                throw new ResponseStatusException(HttpStatus.CONFLICT, "Stock disponível insuficiente");
        }
        for (Item item : request.items()) {
            if (products.get(item.productId().toString()).getPrice().compareTo(item.expectedUnitPrice()) != 0)
                throw new ResponseStatusException(HttpStatus.CONFLICT, "Preço alterado. Atualize os produtos.");
        }
        Customer customer;
        if (request.customerId() != null) {
            customer = em.find(Customer.class, request.customerId().toString());
            if (customer == null)
                throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Cliente não encontrado");
        } else {
            customer = new Customer(request.customer().name(), request.customer().phone());
            em.persist(customer);
        }
        List<SaleItem> items = new ArrayList<>();
        BigDecimal total = BigDecimal.ZERO;
        for (String productId : quantities.keySet()) {
            SaleItem item = new SaleItem(id, products.get(productId), quantities.get(productId));
            items.add(item);
            total = total.add(item.getUnitPrice().multiply(item.getQuantity()).setScale(2, RoundingMode.HALF_UP));
        }
        if (total.precision() - total.scale() > 17)
            throw bad("Total excede o limite permitido");
        Sale sale = new Sale(id, hash, customer.getId(), principal.getName(),
                request.deliverNow() ? Sale.Delivery.DELIVERED : Sale.Delivery.PENDING,
                request.paid() ? Sale.Payment.PAID : Sale.Payment.PENDING, total);
        em.persist(sale);
        for (SaleItem item : items)
            em.persist(item);
        if (request.deliverNow()) {
            for (SaleItem item : items)
                stock.saleExit(item.getProductId(), item.getQuantity(), principal.getName(), id);
        }
        em.flush();
        return view(sale);
    }

    @PatchMapping("/{id}/deliver")
    @Transactional(isolation = Isolation.READ_COMMITTED)
    View deliver(@PathVariable UUID id, Principal principal) {
        Sale sale = locked(id);
        if (sale.getDeliveryStatus() != Sale.Delivery.PENDING)
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Pedido já processado");
        List<SaleItem> items = items(id);
        items.forEach(item -> stock.lockProduct(item.getProductId()));
        sale.changeDelivery(Sale.Delivery.DELIVERED, principal.getName());
        em.flush();
        for (SaleItem item : items)
            stock.saleExit(item.getProductId(), item.getQuantity(), principal.getName(), sale.getId());
        em.flush();
        return view(sale);
    }

    @PatchMapping("/{id}/cancel")
    @Transactional(isolation = Isolation.READ_COMMITTED)
    View cancel(@PathVariable UUID id, Principal principal) {
        Sale sale = locked(id);
        if (sale.getDeliveryStatus() != Sale.Delivery.PENDING || sale.getPaymentStatus() == Sale.Payment.PAID)
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Só pedidos pendentes não pagos podem ser cancelados");
        items(id).forEach(item -> stock.lockProduct(item.getProductId()));
        sale.changeDelivery(Sale.Delivery.CANCELLED, principal.getName());
        em.flush();
        return view(sale);
    }

    @PatchMapping("/{id}/pay")
    @Transactional(isolation = Isolation.READ_COMMITTED)
    View pay(@PathVariable UUID id, Principal principal) {
        Sale sale = locked(id);
        if (sale.getDeliveryStatus() == Sale.Delivery.CANCELLED || sale.getPaymentStatus() == Sale.Payment.PAID)
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Pagamento não pode ser registado");
        sale.paid(principal.getName());
        em.flush();
        return view(sale);
    }

    private Sale locked(UUID id) {
        Sale sale = em.find(Sale.class, id.toString(), LockModeType.PESSIMISTIC_WRITE);
        if (sale == null)
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        return sale;
    }

    private View existingSale(Sale existing, Principal principal, String hash) {
        if (!existing.getSeller().equals(principal.getName()) || !existing.getRequestHash().equals(hash))
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Identificador já utilizado");
        return view(existing);
    }

    private List<SaleItem> items(UUID id) {
        return em.createQuery("select i from SaleItem i where i.saleId = :id order by i.productId", SaleItem.class)
                .setParameter("id", id.toString()).getResultList();
    }

    private ResponseStatusException bad(String message) {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, message);
    }
}
