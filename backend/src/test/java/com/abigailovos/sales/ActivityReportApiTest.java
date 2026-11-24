package com.abigailovos.sales;

import com.abigailovos.customer.Customer;
import jakarta.persistence.EntityManager;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;
import static com.abigailovos.testutil.TestPhones.next;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest @AutoConfigureMockMvc @Transactional
class ActivityReportApiTest {
    @Autowired MockMvc mvc;
    @Autowired EntityManager em;
    @Autowired JdbcTemplate jdbc;

    @Test void reportSeparatesPeriodEventsCurrentDebtsOrdersAndPaymentMethods() throws Exception {
        em.createQuery("delete from SaleItem").executeUpdate();
        em.createQuery("delete from Sale").executeUpdate();
        Customer alice = new Customer("Cliente A", next());
        Customer bob = new Customer("Cliente B", next());
        Customer freeCustomer = new Customer("Cliente oferta", next());
        em.persist(alice);
        em.persist(bob);
        em.persist(freeCustomer);
        Sale paid = sale(alice, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PAID, "100.10", Sale.PaymentMethod.EMOLA);
        Sale debt = sale(alice, "bia", Sale.Delivery.DELIVERED, Sale.Payment.PENDING, "40.20", null);
        Sale oldDebt = sale(bob, "bia", Sale.Delivery.DELIVERED, Sale.Payment.PENDING, "20.05", null);
        sale(bob, "ana", Sale.Delivery.PENDING, Sale.Payment.PENDING, "60.00", null);
        Sale paidOrder = sale(bob, "ana", Sale.Delivery.PENDING, Sale.Payment.PAID, "30.00", Sale.PaymentMethod.MPESA);
        Sale oldMethod = sale(alice, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PAID, "7.70", null);
        Sale unknown = sale(alice, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PAID, "5.00", Sale.PaymentMethod.BANK);
        Sale nextDay = sale(alice, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PAID, "500.00", Sale.PaymentMethod.CASH);
        Sale free = sale(freeCustomer, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PENDING, "0.00", null);
        sale(bob, "ana", Sale.Delivery.CANCELLED, Sale.Payment.PENDING, "1000.00", null);
        em.flush();

        updateDates(paid, "2026-01-04T22:00:00Z", "2026-01-05T10:00:00Z");
        updateDates(debt, "2026-01-10T08:00:00Z", null);
        updateDates(oldDebt, "2025-12-01T12:00:00Z", null);
        updateDates(paidOrder, null, "2026-01-10T09:00:00Z");
        updateDates(oldMethod, "2026-01-11T20:00:00Z", "2026-01-11T20:00:00Z");
        updateDates(unknown, null, null);
        updateDates(nextDay, "2026-01-11T22:00:00Z", "2026-01-11T22:00:00Z");
        updateDates(free, "2025-12-01T12:00:00Z", null);
        jdbc.update("update sales set updated_by='admin' where id=?", paid.getId());
        String product = UUID.randomUUID().toString();
        jdbc.update("insert into products (id, name, unit, price, active, created_at, updated_at) values (?,?,?,?,?,?,?)",
                product, "Ovos exemplo", "bandeja", new BigDecimal("50.05"), true, at("2025-12-01T00:00:00Z"), at("2025-12-01T00:00:00Z"));
        jdbc.update("insert into sale_items (id, sale_id, product_id, product_name, unit, quantity, unit_price) values (?,?,?,?,?,?,?)",
                UUID.randomUUID().toString(), paid.getId(), product, "Ovos exemplo", "bandeja", new BigDecimal("2.00"), new BigDecimal("50.05"));
        em.clear();

        mvc.perform(get("/api/reports/activity").param("from", "2026-01-05").param("to", "2026-01-11")
                .with(user("admin").roles("ADMIN")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.periodStart").value("2026-01-05"))
                .andExpect(jsonPath("$.periodEnd").value("2026-01-11"))
                .andExpect(jsonPath("$.timeZone").value("Africa/Maputo"))
                .andExpect(jsonPath("$.queriedAt").isString())
                .andExpect(jsonPath("$.deliveredAmount").value("148.00"))
                .andExpect(jsonPath("$.debtAmount").value("60.25"))
                .andExpect(jsonPath("$.pendingOrderAmount").value("90.00"))
                .andExpect(jsonPath("$.paidAmount").value("137.80"))
                .andExpect(jsonPath("$.deliveredCustomers.length()").value(1))
                .andExpect(jsonPath("$.deliveredCustomers[0].name").value("Cliente A"))
                .andExpect(jsonPath("$.deliveredCustomers[0].operations").value(3))
                .andExpect(jsonPath("$.deliveredCustomers[0].amount").value("148.00"))
                .andExpect(jsonPath("$.debtCustomers.length()").value(2))
                .andExpect(jsonPath("$.debtCustomers[0].amount").value("40.20"))
                .andExpect(jsonPath("$.debtCustomers[1].amount").value("20.05"))
                .andExpect(jsonPath("$.pendingOrders.length()").value(2))
                .andExpect(jsonPath("$.payments.length()").value(3))
                .andExpect(jsonPath("$.payments[2].items[0].lineTotal").value("100.10"))
                .andExpect(jsonPath("$.paymentMethods[0].method").value("EMOLA"))
                .andExpect(jsonPath("$.paymentMethods[0].amount").value("100.10"))
                .andExpect(jsonPath("$.paymentMethods[1].amount").value("30.00"))
                .andExpect(jsonPath("$.paymentMethods[4].method").value("UNKNOWN"))
                .andExpect(jsonPath("$.paymentMethods[4].amount").value("7.70"))
                .andExpect(jsonPath("$.sellers[0].seller").value("ana"))
                .andExpect(jsonPath("$.sellers[0].amount").value("107.80"))
                .andExpect(jsonPath("$.sellers[1].seller").value("bia"))
                .andExpect(jsonPath("$.sellers[1].amount").value("40.20"))
                .andExpect(jsonPath("$.deliveries.length()").value(3))
                .andExpect(jsonPath("$.deliveries[2].seller").value("ana"))
                .andExpect(jsonPath("$.deliveries[2].createdAt").isString())
                .andExpect(jsonPath("$.deliveries[2].deliveredAt").value("2026-01-04T22:00:00Z"))
                .andExpect(jsonPath("$.deliveries[2].items[0].name").value("Ovos exemplo"))
                .andExpect(jsonPath("$.deliveries[2].items[0].quantity").value("2.00"))
                .andExpect(jsonPath("$.deliveries[2].items[0].unitPrice").value("50.05"))
                .andExpect(jsonPath("$.deliveries[2].items[0].lineTotal").value("100.10"))
                .andExpect(jsonPath("$.unknownDeliveredDates").value(1))
                .andExpect(jsonPath("$.unknownPaidDates").value(1));
    }

    @Test void activityIsAdminOnlyAndRequiresAReasonableCompletePeriod() throws Exception {
        mvc.perform(get("/api/reports/activity").param("from", "2026-01-01").param("to", "2026-01-31"))
                .andExpect(status().isUnauthorized());
        mvc.perform(get("/api/reports/activity").param("from", "2026-01-01").param("to", "2026-01-31")
                .with(user("vendedor").roles("SELLER"))).andExpect(status().isForbidden());
        mvc.perform(get("/api/reports/activity").param("from", "2026-01-01").param("to", "2026-02-01")
                .with(user("admin").roles("ADMIN"))).andExpect(status().isBadRequest());
        mvc.perform(get("/api/reports/activity").param("from", "2026-01-02").param("to", "2026-01-01")
                .with(user("admin").roles("ADMIN"))).andExpect(status().isBadRequest());
        mvc.perform(get("/api/reports/activity").param("from", "2026-01-01")
                .with(user("admin").roles("ADMIN"))).andExpect(status().isBadRequest());
    }

    @Test void debtsAreCurrentButEventsStayInTheirOwnPeriod() throws Exception {
        em.createQuery("delete from SaleItem").executeUpdate();
        em.createQuery("delete from Sale").executeUpdate();
        Customer customer = new Customer("Cliente exemplo", next());
        em.persist(customer);
        Sale delivered = sale(customer, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PENDING, "75.00", null);
        Sale historical = sale(customer, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PENDING, "5.00", null);
        em.flush();
        updateDates(delivered, "2026-01-10T10:00:00Z", null);
        updateDates(historical, null, null);
        em.clear();
        mvc.perform(get("/api/reports/activity").param("from", "2026-01-01").param("to", "2026-01-31")
                .with(user("admin").roles("ADMIN")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.debtAmount").value("80.00"))
                .andExpect(jsonPath("$.paidAmount").value("0.00"))
                .andExpect(jsonPath("$.unknownDeliveredDates").value(1));
        jdbc.update("update sales set payment_status='PAID', payment_method='CASH', paid_at=? where id=?",
                at("2026-02-05T10:00:00Z"), delivered.getId());
        em.clear();
        mvc.perform(get("/api/reports/activity").param("from", "2026-01-01").param("to", "2026-01-31")
                .with(user("admin").roles("ADMIN")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.deliveredAmount").value("75.00"))
                .andExpect(jsonPath("$.debtAmount").value("5.00")).andExpect(jsonPath("$.paidAmount").value("0.00"))
                .andExpect(jsonPath("$.deliveries[0].paymentStatus").value("PAID"));
        mvc.perform(get("/api/reports/activity").param("from", "2026-02-01").param("to", "2026-02-28")
                .with(user("admin").roles("ADMIN")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.deliveredAmount").value("0.00"))
                .andExpect(jsonPath("$.paidAmount").value("75.00"))
                .andExpect(jsonPath("$.paymentMethods[3].method").value("CASH"))
                .andExpect(jsonPath("$.paymentMethods[3].amount").value("75.00"));
    }

    @Test void financialTotalsRemainExactForLargeAmounts() throws Exception {
        em.createQuery("delete from SaleItem").executeUpdate();
        em.createQuery("delete from Sale").executeUpdate();
        Customer customer = new Customer("Cliente precisão", next());
        em.persist(customer);
        Sale first = sale(customer, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PENDING, "90071992547409.91", null);
        Sale second = sale(customer, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PENDING, "0.08", null);
        em.flush();
        updateDates(first, "2026-01-10T10:00:00Z", null);
        updateDates(second, "2026-01-10T10:00:00Z", null);
        em.clear();
        mvc.perform(get("/api/reports/activity").param("from", "2026-01-01").param("to", "2026-01-31")
                .with(user("admin").roles("ADMIN")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.deliveredAmount").value("90071992547409.99"))
                .andExpect(jsonPath("$.debtAmount").value("90071992547409.99"))
                .andExpect(jsonPath("$.deliveredCustomers[0].amount").value("90071992547409.99"))
                .andExpect(jsonPath("$.sellers[0].amount").value("90071992547409.99"));
    }

    @Test void oversizedReportIsRefusedRatherThanSilentlyTruncated() throws Exception {
        em.createQuery("delete from SaleItem").executeUpdate();
        em.createQuery("delete from Sale").executeUpdate();
        Customer customer = new Customer("Cliente volume", next());
        em.persist(customer);
        em.flush();
        Timestamp time = at("2026-01-10T10:00:00Z");
        List<Object[]> rows = new ArrayList<>();
        for (int i = 0; i < 5_001; i++) rows.add(new Object[] {UUID.randomUUID().toString(), "ficticio",
                customer.getId(), "ana", "DELIVERED", "PENDING", BigDecimal.ONE, time, time, "ana", time});
        jdbc.batchUpdate("insert into sales (id, request_hash, customer_id, seller, delivery_status, payment_status, "
                + "total, created_at, updated_at, updated_by, delivered_at) values (?,?,?,?,?,?,?,?,?,?,?)", rows);
        em.clear();
        mvc.perform(get("/api/reports/activity").param("from", "2026-01-01").param("to", "2026-01-31")
                .with(user("admin").roles("ADMIN"))).andExpect(status().isPayloadTooLarge());
    }

    private Sale sale(Customer customer, String seller, Sale.Delivery delivery, Sale.Payment payment,
            String total, Sale.PaymentMethod method) {
        Sale sale = new Sale(UUID.randomUUID().toString(), "ficticio", customer.getId(), seller, delivery, payment,
                new BigDecimal(total), method);
        em.persist(sale);
        return sale;
    }

    private void updateDates(Sale sale, String delivered, String paid) {
        jdbc.update("update sales set delivered_at=?, paid_at=? where id=?", at(delivered), at(paid), sale.getId());
    }

    private Timestamp at(String value) { return value == null ? null : Timestamp.from(Instant.parse(value)); }
}
