package com.abigailovos.sales;

import jakarta.persistence.EntityManager;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/reports")
class SalesReportController {
    private final EntityManager entityManager;

    SalesReportController(EntityManager entityManager) {
        this.entityManager = entityManager;
    }

    record SellerPerformance(String seller, long deliveredCount, String deliveredAmount) {}
    record SalesSummary(long pendingOrders, long deliveredSales, long cancelledOperations,
            long pendingPayments, long markedPaid,
            String deliveredAmount, String markedPaidAmount, String pendingPaymentAmount,
            List<SellerPerformance> sellers) {}

    private static final class SellerTotals {
        long count;
        BigDecimal amount = BigDecimal.ZERO;
    }

    @GetMapping("/sales")
    @Transactional(readOnly = true)
    SalesSummary sales() {
        // One aggregate query gives all figures the same database snapshot.
        List<Object[]> rows = entityManager.createQuery(
                "select s.seller, s.deliveryStatus, s.paymentStatus, count(s), sum(s.total) "
                + "from Sale s group by s.seller, s.deliveryStatus, s.paymentStatus", Object[].class)
                .getResultList();
        long pending = 0, delivered = 0, cancelled = 0, pendingPayments = 0, paid = 0;
        BigDecimal deliveredAmount = BigDecimal.ZERO, paidAmount = BigDecimal.ZERO, pendingAmount = BigDecimal.ZERO;
        Map<String, SellerTotals> bySeller = new TreeMap<>();
        for (Object[] row : rows) {
            String seller = (String) row[0];
            Sale.Delivery delivery = (Sale.Delivery) row[1];
            Sale.Payment payment = (Sale.Payment) row[2];
            long count = (Long) row[3];
            BigDecimal amount = (BigDecimal) row[4];
            if (delivery == Sale.Delivery.CANCELLED) {
                cancelled += count;
                continue;
            }
            if (delivery == Sale.Delivery.PENDING) pending += count;
            if (delivery == Sale.Delivery.DELIVERED) {
                delivered += count;
                deliveredAmount = deliveredAmount.add(amount);
                SellerTotals totals = bySeller.computeIfAbsent(seller, ignored -> new SellerTotals());
                totals.count += count;
                totals.amount = totals.amount.add(amount);
            }
            if (payment == Sale.Payment.PAID) {
                paid += count;
                paidAmount = paidAmount.add(amount);
            } else {
                pendingPayments += count;
                pendingAmount = pendingAmount.add(amount);
            }
        }
        List<SellerPerformance> sellers = new ArrayList<>();
        bySeller.forEach((name, totals) -> sellers.add(new SellerPerformance(name, totals.count, money(totals.amount))));
        return new SalesSummary(pending, delivered, cancelled, pendingPayments, paid,
                money(deliveredAmount), money(paidAmount), money(pendingAmount), sellers);
    }

    private static String money(BigDecimal amount) {
        return amount.setScale(2).toPlainString();
    }
}
