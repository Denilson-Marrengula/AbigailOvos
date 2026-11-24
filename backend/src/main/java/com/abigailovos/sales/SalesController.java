package com.abigailovos.sales;

import com.abigailovos.customer.Customer;
import com.abigailovos.customer.CustomerPhoneConflict;
import com.abigailovos.audit.AuditLog;
import com.abigailovos.product.Product;
import com.abigailovos.stock.StockService;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.security.MessageDigest;
import java.security.Principal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.DateTimeException;
import java.util.*;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
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
    private final AuditLog audit;

    SalesController(EntityManager em, StockService stock, ObjectMapper json, AuditLog audit) {
        this.em = em;
        this.stock = stock;
        this.json = json;
        this.audit = audit;
    }

    record NewCustomer(@NotBlank @Size(max = 150) String name, @Size(max = 40) String phone) {
    }

    record Item(@NotNull UUID productId,
            @NotNull @DecimalMin(value = "0", inclusive = false) @Digits(integer = 17, fraction = 2) BigDecimal quantity,
            @NotNull @DecimalMin("0") @Digits(integer = 17, fraction = 2) BigDecimal expectedUnitPrice) {
    }

    record Create(@NotNull UUID id, UUID customerId, @Valid NewCustomer customer,
            @NotEmpty @Size(max = 100) List<@NotNull @Valid Item> items,
            @NotNull Boolean deliverNow, @NotNull Boolean paid,
            @JsonInclude(JsonInclude.Include.NON_NULL) Sale.PaymentMethod paymentMethod) {
    }

    record Pay(@NotNull Sale.PaymentMethod method) {}

    record Capabilities(boolean paymentMethods, boolean sellerSalesIsolation, boolean adminSaleAssistance,
            boolean customerPhoneUnique) {}

    record View(String id, String customerId, String customerName, String seller, Sale.Delivery deliveryStatus,
            Sale.Payment paymentStatus, Sale.PaymentMethod paymentMethod, BigDecimal total, String totalText, Instant createdAt, List<SaleItem> items) {
    }

    record SearchPage(List<View> items, int page, boolean hasMore) {}

    private View view(Sale sale) {
        Customer customer = em.find(Customer.class, sale.getCustomerId());
        List<SaleItem> items = em
                .createQuery("select i from SaleItem i where i.saleId = :id order by i.productName", SaleItem.class)
                .setParameter("id", sale.getId()).getResultList();
        return new View(sale.getId(), sale.getCustomerId(), customer.getName(), sale.getSeller(),
                sale.getDeliveryStatus(),
                sale.getPaymentStatus(), sale.getPaymentMethod(), sale.getTotal(), sale.getTotal().toPlainString(), sale.getCreatedAt(), items);
    }

    @GetMapping
    @Transactional(readOnly = true)
    List<View> list(Authentication auth) {
        if (isAdmin(auth)) {
            return em.createQuery("select s from Sale s order by s.createdAt desc", Sale.class).getResultList().stream()
                    .map(this::view).toList();
        }
        // Database collations may equate different names. Filter exact identities
        // before constructing views, not just in the database predicate.
        return em.createQuery("select s from Sale s where s.seller = :seller order by s.createdAt desc", Sale.class)
                .setParameter("seller", auth.getName()).getResultList().stream()
                .filter(sale -> ownedBy(sale, auth)).map(this::view).toList();
    }

    @GetMapping("/search")
    @Transactional(readOnly = true)
    SearchPage search(Authentication auth,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(required = false) String customer,
            @RequestParam(required = false) String product,
            @RequestParam(required = false) String seller,
            @RequestParam(defaultValue = "ALL") String state,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        if (page < 0 || page > 10_000 || size < 1 || size > 100)
            throw bad("Paginação inválida");
        if ((from == null) != (to == null) || (from != null && from.isAfter(to)))
            throw bad("Indique um período válido com início e fim");
        customer = searchTerm(customer);
        product = searchTerm(product);
        seller = searchTerm(seller);
        if (!isAdmin(auth) && seller != null && !seller.equals(auth.getName()))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Apenas as próprias operações podem ser consultadas");
        String exactSeller = isAdmin(auth) ? seller : auth.getName();

        StringBuilder hql = new StringBuilder("select s from Sale s where 1=1");
        if (exactSeller != null) hql.append(" and s.seller = :seller");
        if (customer != null) hql.append(" and exists (select c.id from Customer c where c.id = s.customerId and lower(c.name) like :customer escape '!')");
        if (product != null) hql.append(" and exists (select i.id from SaleItem i where i.saleId = s.id and lower(i.productName) like :product escape '!')");
        switch (state) {
            case "ALL" -> { }
            case "PENDING_DELIVERY" -> hql.append(" and s.deliveryStatus = :pendingDelivery");
            case "PENDING_PAYMENT" -> hql.append(" and s.deliveryStatus <> :cancelled and s.paymentStatus = :pendingPayment");
            case "DELIVERED" -> hql.append(" and s.deliveryStatus = :delivered");
            case "CANCELLED" -> hql.append(" and s.deliveryStatus = :cancelled");
            default -> throw bad("Filtro de estado inválido");
        }
        if (from != null) hql.append(" and s.createdAt >= :start and s.createdAt < :end");
        hql.append(" order by s.createdAt desc, s.id desc");
        var query = em.createQuery(hql.toString(), Sale.class);
        if (exactSeller != null) query.setParameter("seller", exactSeller);
        if (customer != null) query.setParameter("customer", likeTerm(customer));
        if (product != null) query.setParameter("product", likeTerm(product));
        if (state.equals("PENDING_DELIVERY")) query.setParameter("pendingDelivery", Sale.Delivery.PENDING);
        if (state.equals("PENDING_PAYMENT")) query.setParameter("cancelled", Sale.Delivery.CANCELLED)
                .setParameter("pendingPayment", Sale.Payment.PENDING);
        if (state.equals("DELIVERED")) query.setParameter("delivered", Sale.Delivery.DELIVERED);
        if (state.equals("CANCELLED")) query.setParameter("cancelled", Sale.Delivery.CANCELLED);
        if (from != null) {
            try {
                ZoneId zone = ZoneId.of("Africa/Maputo");
                query.setParameter("start", from.atStartOfDay(zone).toInstant())
                        .setParameter("end", to.plusDays(1).atStartOfDay(zone).toInstant());
            } catch (DateTimeException ex) {
                throw bad("Período fora do intervalo permitido");
            }
        }

        // A case-insensitive DB may match another username. Check exact ownership
        // before pagination, constructing views or deciding whether there is a next page.
        int skip = page * size, offset = 0;
        int chunkSize = 100;
        List<View> result = new ArrayList<>();
        boolean hasMore = false, done = false;
        while (!done) {
            List<Sale> chunk = query.setFirstResult(offset).setMaxResults(chunkSize).getResultList();
            for (Sale sale : chunk) {
                if (exactSeller != null && !sale.getSeller().equals(exactSeller)) continue;
                if (skip > 0) { skip--; continue; }
                if (result.size() == size) { hasMore = true; done = true; break; }
                result.add(view(sale));
            }
            if (chunk.size() < chunkSize) break;
            offset += chunk.size();
        }
        return new SearchPage(result, page, hasMore);
    }

    private String searchTerm(String value) {
        if (value == null || value.isBlank()) return null;
        String result = value.strip();
        if (result.length() > 150) throw bad("Pesquisa demasiado longa");
        return result;
    }

    private String likeTerm(String value) {
        return "%" + value.toLowerCase(Locale.ROOT).replace("!", "!!").replace("%", "!%")
                .replace("_", "!_") + "%";
    }

    @GetMapping("/capabilities")
    Capabilities capabilities() {
        return new Capabilities(true, true, true, true);
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
        if (request.paid() && request.paymentMethod() == null)
            throw bad("Selecione o meio de pagamento");
        if (!request.paid() && request.paymentMethod() != null)
            throw bad("Indique o meio apenas quando o pagamento for registado");
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
            try {
                customer = new Customer(request.customer().name(), request.customer().phone());
            } catch (IllegalArgumentException ex) {
                throw bad("Telefone obrigatório ou inválido");
            }
            CustomerPhoneConflict.insertCustomer(em, customer);
            audit.record(principal.getName(), "CUSTOMER_CREATED", "CUSTOMER", customer.getId(), "origin=SALE");
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
                request.paid() ? Sale.Payment.PAID : Sale.Payment.PENDING, total, request.paymentMethod());
        em.persist(sale);
        audit.record(principal.getName(), "SALE_CREATED", "SALE", id,
                "delivery=" + sale.getDeliveryStatus() + ";payment=" + sale.getPaymentStatus()
                + (sale.getPaymentMethod() == null ? "" : ";method=" + sale.getPaymentMethod()));
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
    View deliver(@PathVariable UUID id, Authentication principal) {
        Sale sale = locked(id);
        requireAccess(sale, principal, true);
        if (sale.getDeliveryStatus() != Sale.Delivery.PENDING)
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Pedido já processado");
        List<SaleItem> items = items(id);
        items.forEach(item -> stock.lockProduct(item.getProductId()));
        sale.changeDelivery(Sale.Delivery.DELIVERED, principal.getName());
        audit.record(principal.getName(), "SALE_DELIVERED", "SALE", sale.getId(), "delivery=DELIVERED");
        em.flush();
        for (SaleItem item : items)
            stock.saleExit(item.getProductId(), item.getQuantity(), principal.getName(), sale.getId());
        em.flush();
        return view(sale);
    }

    @PatchMapping("/{id}/cancel")
    @Transactional(isolation = Isolation.READ_COMMITTED)
    View cancel(@PathVariable UUID id, Authentication principal) {
        Sale sale = locked(id);
        requireAccess(sale, principal, false);
        if (sale.getDeliveryStatus() != Sale.Delivery.PENDING || sale.getPaymentStatus() == Sale.Payment.PAID)
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Só pedidos pendentes não pagos podem ser cancelados");
        items(id).forEach(item -> stock.lockProduct(item.getProductId()));
        sale.changeDelivery(Sale.Delivery.CANCELLED, principal.getName());
        audit.record(principal.getName(), "SALE_CANCELLED", "SALE", sale.getId(), "delivery=CANCELLED");
        em.flush();
        return view(sale);
    }

    @PatchMapping("/{id}/pay")
    @Transactional(isolation = Isolation.READ_COMMITTED)
    View pay(@PathVariable UUID id, @Valid @RequestBody Pay request, Authentication principal) {
        Sale sale = locked(id);
        requireAccess(sale, principal, true);
        if (sale.getDeliveryStatus() == Sale.Delivery.CANCELLED || sale.getPaymentStatus() == Sale.Payment.PAID)
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Pagamento não pode ser registado");
        sale.paid(principal.getName(), request.method());
        audit.record(principal.getName(), "SALE_MARKED_PAID", "SALE", sale.getId(), "payment=PAID;method=" + request.method());
        em.flush();
        return view(sale);
    }

    private Sale locked(UUID id) {
        Sale sale = em.find(Sale.class, id.toString(), LockModeType.PESSIMISTIC_WRITE);
        if (sale == null)
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        return sale;
    }

    private boolean isAdmin(Authentication auth) {
        return auth.getAuthorities().stream().anyMatch(role -> "ROLE_ADMIN".equals(role.getAuthority()));
    }

    private boolean ownedBy(Sale sale, Authentication auth) {
        return sale.getSeller().equals(auth.getName());
    }

    private void requireAccess(Sale sale, Authentication auth, boolean allowAdmin) {
        if (!ownedBy(sale, auth) && !(allowAdmin && isAdmin(auth)))
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
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
