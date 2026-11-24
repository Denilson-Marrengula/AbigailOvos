package com.abigailovos.sales;

import jakarta.persistence.EntityManager;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.DateTimeException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import static org.springframework.http.HttpStatus.BAD_REQUEST;

@RestController
@RequestMapping("/api/reports")
class SalesReportController {
    private static final ZoneId REPORT_ZONE = ZoneId.of("Africa/Maputo");
    private final EntityManager entityManager;

    SalesReportController(EntityManager entityManager) {
        this.entityManager = entityManager;
    }

    record SellerPerformance(String seller, long deliveredCount, String deliveredAmount) {}
    record SalesSummary(long pendingOrders, long deliveredSales, long cancelledOperations,
            long pendingPayments, long markedPaid,
            String deliveredAmount, String markedPaidAmount, String pendingPaymentAmount,
            List<SellerPerformance> sellers, long unknownDeliveredDates, long unknownPaidDates,
            long unknownCancelledDates, String periodStart, String periodEnd, String timeZone) {}

    private static final class SellerTotals {
        long count;
        BigDecimal amount = BigDecimal.ZERO;
    }

    @GetMapping("/sales")
    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    SalesSummary sales(@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        if ((from == null) != (to == null) || (from != null && from.isAfter(to)))
            throw new ResponseStatusException(BAD_REQUEST, "Indique um período válido com início e fim");
        Instant start = null, end = null;
        try {
            if (from != null) {
                start = from.atStartOfDay(REPORT_ZONE).toInstant();
                end = to.plusDays(1).atStartOfDay(REPORT_ZONE).toInstant();
            }
        } catch (DateTimeException ex) {
            throw new ResponseStatusException(BAD_REQUEST, "Período fora do intervalo permitido");
        }

        // Pending balances are a current snapshot, not payments or deliveries in the chosen period.
        List<Object[]> pendingRows = entityManager.createQuery(
                "select s.deliveryStatus, s.paymentStatus, count(s), sum(s.total) "
                + "from Sale s where s.deliveryStatus <> :cancelled group by s.deliveryStatus, s.paymentStatus",
                Object[].class).setParameter("cancelled", Sale.Delivery.CANCELLED).getResultList();
        long pending = 0, pendingPayments = 0;
        BigDecimal pendingAmount = BigDecimal.ZERO;
        for (Object[] row : pendingRows) {
            Sale.Delivery delivery = (Sale.Delivery) row[0];
            Sale.Payment payment = (Sale.Payment) row[1];
            long count = (Long) row[2];
            if (delivery == Sale.Delivery.PENDING) pending += count;
            if (payment == Sale.Payment.PENDING) {
                pendingPayments += count;
                pendingAmount = pendingAmount.add((BigDecimal) row[3]);
            }
        }

        long delivered = 0, paid = 0;
        BigDecimal deliveredAmount = BigDecimal.ZERO, paidAmount = BigDecimal.ZERO;
        Map<String, SellerTotals> bySeller = new TreeMap<>();
        String deliveredFilter = start == null ? "" : " and s.deliveredAt >= :start and s.deliveredAt < :end";
        var deliveries = entityManager.createQuery(
                "select s.seller, count(s), sum(s.total) from Sale s where s.deliveryStatus = :status"
                + deliveredFilter + " group by s.seller", Object[].class)
                .setParameter("status", Sale.Delivery.DELIVERED);
        if (start != null) deliveries.setParameter("start", start).setParameter("end", end);
        for (Object[] row : deliveries.getResultList()) {
            String seller = (String) row[0];
            long count = (Long) row[1];
            BigDecimal amount = (BigDecimal) row[2];
            delivered += count;
            deliveredAmount = deliveredAmount.add(amount);
            SellerTotals totals = bySeller.computeIfAbsent(seller, ignored -> new SellerTotals());
            totals.count += count;
            totals.amount = totals.amount.add(amount);
        }

        String paidFilter = start == null ? "" : " and s.paidAt >= :start and s.paidAt < :end";
        var payments = entityManager.createQuery(
                "select count(s), sum(s.total) from Sale s where s.paymentStatus = :paid and s.deliveryStatus <> :cancelled"
                + paidFilter, Object[].class).setParameter("paid", Sale.Payment.PAID)
                .setParameter("cancelled", Sale.Delivery.CANCELLED);
        if (start != null) payments.setParameter("start", start).setParameter("end", end);
        Object[] paidRow = payments.getSingleResult();
        paid = (Long) paidRow[0];
        if (paidRow[1] != null) paidAmount = (BigDecimal) paidRow[1];

        String cancelledFilter = start == null ? "" : " and s.cancelledAt >= :start and s.cancelledAt < :end";
        var cancellations = entityManager.createQuery(
                "select count(s) from Sale s where s.deliveryStatus = :cancelled" + cancelledFilter, Long.class)
                .setParameter("cancelled", Sale.Delivery.CANCELLED);
        if (start != null) cancellations.setParameter("start", start).setParameter("end", end);
        long cancelled = cancellations.getSingleResult();

        long unknownDelivered = entityManager.createQuery(
                "select count(s) from Sale s where s.deliveryStatus = :status and s.deliveredAt is null", Long.class)
                .setParameter("status", Sale.Delivery.DELIVERED).getSingleResult();
        long unknownPaid = entityManager.createQuery(
                "select count(s) from Sale s where s.paymentStatus = :paid and s.deliveryStatus <> :cancelled and s.paidAt is null", Long.class)
                .setParameter("paid", Sale.Payment.PAID).setParameter("cancelled", Sale.Delivery.CANCELLED).getSingleResult();
        long unknownCancelled = entityManager.createQuery(
                "select count(s) from Sale s where s.deliveryStatus = :status and s.cancelledAt is null", Long.class)
                .setParameter("status", Sale.Delivery.CANCELLED).getSingleResult();

        List<SellerPerformance> sellers = new ArrayList<>();
        bySeller.forEach((name, totals) -> sellers.add(new SellerPerformance(name, totals.count, money(totals.amount))));
        return new SalesSummary(pending, delivered, cancelled, pendingPayments, paid,
                money(deliveredAmount), money(paidAmount), money(pendingAmount), sellers,
                unknownDelivered, unknownPaid, unknownCancelled,
                from == null ? null : from.toString(), to == null ? null : to.toString(), REPORT_ZONE.getId());
    }

    private static String money(BigDecimal amount) {
        return amount.setScale(2).toPlainString();
    }
}
