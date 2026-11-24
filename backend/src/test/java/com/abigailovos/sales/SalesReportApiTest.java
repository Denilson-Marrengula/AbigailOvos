package com.abigailovos.sales;

import com.abigailovos.customer.Customer;
import jakarta.persistence.EntityManager;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static com.abigailovos.testutil.TestPhones.next;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest @AutoConfigureMockMvc @Transactional
class SalesReportApiTest {
    @Autowired MockMvc mvc;
    @Autowired EntityManager em;
    @Autowired JdbcTemplate jdbc;

    @Test void reportsUseExactValuesExcludeCancelledAndEnforceRoles() throws Exception {
        em.createQuery("delete from SaleItem").executeUpdate();
        em.createQuery("delete from Sale").executeUpdate();
        Customer customer = new Customer("Cliente teste", next());
        em.persist(customer);
        create(customer, "ana", Sale.Delivery.PENDING, Sale.Payment.PAID, "10.10");
        create(customer, "ana", Sale.Delivery.PENDING, Sale.Payment.PENDING, "20.05");
        create(customer, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PAID, "30.25");
        create(customer, "bia", Sale.Delivery.DELIVERED, Sale.Payment.PENDING, "40.00");
        create(customer, "bia", Sale.Delivery.CANCELLED, Sale.Payment.PENDING, "50.00");
        em.flush();
        mvc.perform(get("/api/reports/sales").with(user("admin").roles("ADMIN")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.pendingOrders").value(2))
                .andExpect(jsonPath("$.deliveredSales").value(2))
                .andExpect(jsonPath("$.cancelledOperations").value(1))
                .andExpect(jsonPath("$.pendingPayments").value(2))
                .andExpect(jsonPath("$.markedPaid").value(2))
                .andExpect(jsonPath("$.deliveredAmount").value("70.25"))
                .andExpect(jsonPath("$.markedPaidAmount").value("40.35"))
                .andExpect(jsonPath("$.pendingPaymentAmount").value("60.05"))
                .andExpect(jsonPath("$.sellers[0].seller").value("ana"))
                .andExpect(jsonPath("$.sellers[0].deliveredAmount").value("30.25"))
                .andExpect(jsonPath("$.sellers[1].seller").value("bia"))
                .andExpect(jsonPath("$.sellers[1].deliveredAmount").value("40.00"));
        mvc.perform(get("/api/reports/sales").with(user("seller").roles("SELLER"))).andExpect(status().isForbidden());
        mvc.perform(get("/api/reports/sales")).andExpect(status().isUnauthorized());
    }

    private void create(Customer customer, String seller, Sale.Delivery delivery, Sale.Payment payment, String total) {
        em.persist(new Sale(UUID.randomUUID().toString(), "teste", customer.getId(), seller, delivery, payment, new BigDecimal(total), null));
    }

    @Test void emptyAndLargeDecimalTotalsRemainExact() throws Exception {
        em.createQuery("delete from SaleItem").executeUpdate();
        em.createQuery("delete from Sale").executeUpdate();
        mvc.perform(get("/api/reports/sales").with(user("admin").roles("ADMIN")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.deliveredAmount").value("0.00"))
                .andExpect(jsonPath("$.sellers.length()").value(0));
        Customer customer = new Customer("Precisão", next());
        em.persist(customer);
        create(customer, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PAID, "90071992547409.91");
        create(customer, "ana", Sale.Delivery.DELIVERED, Sale.Payment.PAID, "0.08");
        em.flush();
        mvc.perform(get("/api/reports/sales").with(user("admin").roles("ADMIN")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.deliveredAmount").value("90071992547409.99"))
                .andExpect(jsonPath("$.markedPaidAmount").value("90071992547409.99"));
    }

    @Test void periodUsesEventDatesInMaputoAndNeverInventsHistoricalDates() throws Exception {
        em.createQuery("delete from SaleItem").executeUpdate();
        em.createQuery("delete from Sale").executeUpdate();
        Customer customer = new Customer("Cliente período", next());
        em.persist(customer);
        Sale inPeriod = sale(customer, Sale.Delivery.DELIVERED, Sale.Payment.PAID, "10.25");
        Sale nextDay = sale(customer, Sale.Delivery.DELIVERED, Sale.Payment.PAID, "20.00");
        Sale unknown = sale(customer, Sale.Delivery.DELIVERED, Sale.Payment.PAID, "30.00");
        sale(customer, Sale.Delivery.PENDING, Sale.Payment.PENDING, "40.00");
        Sale cancelled = sale(customer, Sale.Delivery.CANCELLED, Sale.Payment.PENDING, "50.00");
        em.flush();
        jdbc.update("update sales set delivered_at=?, paid_at=? where id=?",
                at("2025-12-31T22:00:00Z"), at("2026-01-01T21:59:59Z"), inPeriod.getId());
        jdbc.update("update sales set delivered_at=?, paid_at=? where id=?",
                at("2026-01-01T22:00:00Z"), at("2026-01-01T22:00:00Z"), nextDay.getId());
        jdbc.update("update sales set delivered_at=null, paid_at=null where id=?", unknown.getId());
        jdbc.update("update sales set cancelled_at=null where id=?", cancelled.getId());
        em.clear();

        mvc.perform(get("/api/reports/sales").param("from", "2026-01-01").param("to", "2026-01-01")
                .with(user("admin").roles("ADMIN")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.timeZone").value("Africa/Maputo"))
                .andExpect(jsonPath("$.deliveredSales").value(1)).andExpect(jsonPath("$.deliveredAmount").value("10.25"))
                .andExpect(jsonPath("$.markedPaid").value(1)).andExpect(jsonPath("$.markedPaidAmount").value("10.25"))
                .andExpect(jsonPath("$.pendingOrders").value(1)).andExpect(jsonPath("$.pendingPayments").value(1))
                .andExpect(jsonPath("$.unknownDeliveredDates").value(1)).andExpect(jsonPath("$.unknownPaidDates").value(1))
                .andExpect(jsonPath("$.unknownCancelledDates").value(1));
        mvc.perform(get("/api/reports/sales").with(user("admin").roles("ADMIN")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.deliveredSales").value(3))
                .andExpect(jsonPath("$.markedPaid").value(3)).andExpect(jsonPath("$.cancelledOperations").value(1));
        mvc.perform(get("/api/reports/sales").param("from", "2026-01-02").param("to", "2026-01-01")
                .with(user("admin").roles("ADMIN"))).andExpect(status().isBadRequest());
        mvc.perform(get("/api/reports/sales").param("from", "2026-01-01")
                .with(user("admin").roles("ADMIN"))).andExpect(status().isBadRequest());
        mvc.perform(get("/api/reports/sales").param("from", "2026-01-01").param("to", "2026-01-01")
                .with(user("seller").roles("SELLER"))).andExpect(status().isForbidden());
    }

    private Sale sale(Customer customer, Sale.Delivery delivery, Sale.Payment payment, String total) {
        Sale sale = new Sale(UUID.randomUUID().toString(), "teste", customer.getId(), "ana", delivery, payment,
                new BigDecimal(total), null);
        em.persist(sale);
        return sale;
    }

    private Timestamp at(String value) { return Timestamp.from(Instant.parse(value)); }
}
