package com.abigailovos.sales;

import com.abigailovos.customer.Customer;
import jakarta.persistence.EntityManager;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.DateTimeException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/** On-demand administrative report; no historical state is reconstructed. */
@RestController
@RequestMapping("/api/reports")
class ActivityReportController {
    private static final ZoneId ZONE = ZoneId.of("Africa/Maputo");
    // Fail explicitly rather than silently returning an incomplete financial report.
    private static final int MAX_ROWS = 5_000;
    private static final int MAX_ITEMS = 50_000;
    private final EntityManager em;

    ActivityReportController(EntityManager em) { this.em = em; }

    record CustomerTotal(String customerId, String name, String phone, long operations, String amount) {}
    record MethodTotal(String method, long operations, String amount) {}
    record SellerTotal(String seller, long operations, String amount) {}
    record Item(String name, String unit, String quantity, String unitPrice, String lineTotal) {}
    record Operation(String id, String customerName, String customerPhone, String seller, String amount,
            Instant createdAt, Instant deliveredAt, Instant paidAt, Sale.Delivery deliveryStatus,
            Sale.Payment paymentStatus, Sale.PaymentMethod paymentMethod, List<Item> items) {}
    record Report(String periodStart, String periodEnd, String timeZone, Instant queriedAt,
            long unknownDeliveredDates, long unknownPaidDates, String deliveredAmount, String debtAmount,
            String pendingOrderAmount, String paidAmount, List<CustomerTotal> deliveredCustomers,
            List<CustomerTotal> debtCustomers, List<Operation> pendingOrders, List<MethodTotal> paymentMethods,
            List<Operation> payments, List<SellerTotal> sellers, List<Operation> deliveries) {}

    private static final class Totals {
        final Customer customer;
        long count;
        BigDecimal amount = BigDecimal.ZERO;
        Totals(Customer customer) { this.customer = customer; }
        CustomerTotal view() {
            return new CustomerTotal(customer.getId(), customer.getName(), customer.getPhone(), count, money(amount));
        }
    }

    private static final class SellerTotals {
        long count;
        BigDecimal amount = BigDecimal.ZERO;
    }

    @GetMapping("/activity")
    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    Report report(@RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        if (from.isAfter(to) || ChronoUnit.DAYS.between(from, to) > 30)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Indique um período de até 31 dias");
        Instant start;
        Instant end;
        try {
            start = from.atStartOfDay(ZONE).toInstant();
            end = to.plusDays(1).atStartOfDay(ZONE).toInstant();
        } catch (DateTimeException ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Período inválido");
        }

        // All queries share the same repeatable-read transaction. Period totals
        // use event dates; debts and pending orders are the current snapshot.
        List<Object[]> deliveredRows = bounded(em.createQuery(
                "select s, c from Sale s, Customer c where c.id = s.customerId "
                + "and s.deliveryStatus = :delivered and s.deliveredAt >= :start and s.deliveredAt < :end "
                + "order by s.deliveredAt desc, s.id desc", Object[].class)
                .setParameter("delivered", Sale.Delivery.DELIVERED).setParameter("start", start).setParameter("end", end)
                .setMaxResults(MAX_ROWS + 1).getResultList());
        List<Object[]> paymentRows = bounded(em.createQuery(
                "select s, c from Sale s, Customer c where c.id = s.customerId "
                + "and s.paymentStatus = :paid and s.deliveryStatus <> :cancelled "
                + "and s.paidAt >= :start and s.paidAt < :end order by s.paidAt desc, s.id desc", Object[].class)
                .setParameter("paid", Sale.Payment.PAID).setParameter("cancelled", Sale.Delivery.CANCELLED)
                .setParameter("start", start).setParameter("end", end)
                .setMaxResults(MAX_ROWS + 1).getResultList());
        List<Object[]> pendingRows = bounded(em.createQuery(
                "select s, c from Sale s, Customer c where c.id = s.customerId and s.deliveryStatus = :pending "
                + "order by s.createdAt desc, s.id desc", Object[].class)
                .setParameter("pending", Sale.Delivery.PENDING).setMaxResults(MAX_ROWS + 1).getResultList());
        List<Object[]> debtRows = bounded(em.createQuery(
                "select c.id, c.name, c.phone, count(s), sum(s.total) from Sale s, Customer c "
                + "where c.id = s.customerId and s.deliveryStatus = :delivered and s.paymentStatus = :pending and s.total > 0 "
                + "group by c.id, c.name, c.phone order by c.name, c.id", Object[].class)
                .setParameter("delivered", Sale.Delivery.DELIVERED).setParameter("pending", Sale.Payment.PENDING)
                .setMaxResults(MAX_ROWS + 1).getResultList());

        Map<String, Totals> customers = new LinkedHashMap<>();
        Map<String, SellerTotals> sellers = new java.util.TreeMap<>();
        for (Object[] row : deliveredRows) {
            Sale sale = (Sale) row[0];
            Customer customer = (Customer) row[1];
            Totals totals = customers.computeIfAbsent(customer.getId(), ignored -> new Totals(customer));
            totals.count++;
            totals.amount = totals.amount.add(sale.getTotal());
            SellerTotals seller = sellers.computeIfAbsent(sale.getSeller(), ignored -> new SellerTotals());
            seller.count++;
            seller.amount = seller.amount.add(sale.getTotal());
        }
        List<CustomerTotal> deliveredCustomers = customers.values().stream().map(Totals::view)
                .sorted(Comparator.comparing(CustomerTotal::name).thenComparing(CustomerTotal::customerId)).toList();
        List<CustomerTotal> debts = debtRows.stream().map(row -> new CustomerTotal((String) row[0], (String) row[1],
                (String) row[2], (Long) row[3], money((BigDecimal) row[4]))).toList();
        BigDecimal debtAmount = debtRows.stream().map(row -> (BigDecimal) row[4]).reduce(BigDecimal.ZERO, BigDecimal::add);
        List<SellerTotal> sellerTotals = new ArrayList<>();
        sellers.forEach((name, total) -> sellerTotals.add(new SellerTotal(name, total.count, money(total.amount))));

        Map<String, Long> methodCounts = new LinkedHashMap<>();
        Map<String, BigDecimal> methodAmounts = new LinkedHashMap<>();
        for (String method : List.of("EMOLA", "MPESA", "BANK", "CASH", "UNKNOWN")) {
            methodCounts.put(method, 0L);
            methodAmounts.put(method, BigDecimal.ZERO);
        }
        for (Object[] row : paymentRows) {
            Sale sale = (Sale) row[0];
            String method = sale.getPaymentMethod() == null ? "UNKNOWN" : sale.getPaymentMethod().name();
            methodCounts.put(method, methodCounts.get(method) + 1);
            methodAmounts.put(method, methodAmounts.get(method).add(sale.getTotal()));
        }
        List<MethodTotal> methods = new ArrayList<>();
        methodCounts.forEach((method, count) -> methods.add(new MethodTotal(method, count, money(methodAmounts.get(method)))));

        // Fetch item snapshots in batches instead of one query per operation.
        Map<String, List<Item>> items = new LinkedHashMap<>();
        for (List<Object[]> rows : List.of(deliveredRows, paymentRows, pendingRows))
            for (Object[] row : rows) items.putIfAbsent(((Sale) row[0]).getId(), new ArrayList<>());
        List<String> ids = new ArrayList<>(items.keySet());
        int itemCount = 0;
        for (int first = 0; first < ids.size(); first += 500) {
            List<Object[]> batch = em.createQuery(
                    "select i.saleId, i.productName, i.unit, i.quantity, i.unitPrice from SaleItem i "
                    + "where i.saleId in :ids order by i.saleId, i.productName, i.id", Object[].class)
                    .setParameter("ids", ids.subList(first, Math.min(first + 500, ids.size())))
                    .setMaxResults(MAX_ITEMS - itemCount + 1).getResultList();
            itemCount += batch.size();
            if (itemCount > MAX_ITEMS) throw tooLarge();
            for (Object[] row : batch) {
                BigDecimal quantity = (BigDecimal) row[3];
                BigDecimal price = (BigDecimal) row[4];
                items.get((String) row[0]).add(new Item((String) row[1], (String) row[2], quantity.toPlainString(),
                        money(price), quantity.multiply(price).setScale(2, RoundingMode.HALF_UP).toPlainString()));
            }
        }

        long unknownDelivered = em.createQuery(
                "select count(s) from Sale s where s.deliveryStatus = :status and s.deliveredAt is null", Long.class)
                .setParameter("status", Sale.Delivery.DELIVERED).getSingleResult();
        long unknownPaid = em.createQuery(
                "select count(s) from Sale s where s.paymentStatus = :paid and s.deliveryStatus <> :cancelled and s.paidAt is null", Long.class)
                .setParameter("paid", Sale.Payment.PAID).setParameter("cancelled", Sale.Delivery.CANCELLED).getSingleResult();
        return new Report(from.toString(), to.toString(), ZONE.getId(), Instant.now(), unknownDelivered, unknownPaid,
                sum(deliveredRows), money(debtAmount), sum(pendingRows), sum(paymentRows), deliveredCustomers, debts,
                operations(pendingRows, items), methods, operations(paymentRows, items), sellerTotals,
                operations(deliveredRows, items));
    }

    private static List<Operation> operations(List<Object[]> rows, Map<String, List<Item>> items) {
        return rows.stream().map(row -> {
            Sale sale = (Sale) row[0];
            Customer customer = (Customer) row[1];
            return new Operation(sale.getId(), customer.getName(), customer.getPhone(), sale.getSeller(),
                    money(sale.getTotal()), sale.getCreatedAt(), sale.getDeliveredAt(), sale.getPaidAt(),
                    sale.getDeliveryStatus(), sale.getPaymentStatus(), sale.getPaymentMethod(), items.get(sale.getId()));
        }).toList();
    }

    private static <T> List<T> bounded(List<T> rows) {
        if (rows.size() > MAX_ROWS) throw tooLarge();
        return rows;
    }

    private static ResponseStatusException tooLarge() {
        return new ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE,
                "Relatório demasiado grande; é necessária uma consulta paginada");
    }

    private static String sum(List<Object[]> rows) {
        return money(rows.stream().map(row -> ((Sale) row[0]).getTotal()).reduce(BigDecimal.ZERO, BigDecimal::add));
    }

    private static String money(BigDecimal value) { return value.setScale(2).toPlainString(); }
}
