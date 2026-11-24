package com.abigailovos.customer;

import jakarta.persistence.EntityManager;
import java.sql.SQLException;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/** Translate duplicate-key failures only at a flush that changes a customer. */
public final class CustomerPhoneConflict extends RuntimeException {
    private CustomerPhoneConflict() { super("Telefone já registado"); }

    public static void flushCustomer(EntityManager em) {
        execute(() -> em.flush());
    }

    public static void insertCustomer(EntityManager em, Customer customer) {
        execute(() -> {
            em.persist(customer);
            em.flush();
        });
    }

    private static void execute(Runnable write) {
        try {
            write.run();
        } catch (RuntimeException error) {
            for (Throwable cause = error; cause != null; cause = cause.getCause()) {
                if (cause instanceof SQLException sql
                        && (sql.getErrorCode() == 1062 || "23505".equals(sql.getSQLState()))) {
                    throw new CustomerPhoneConflict();
                }
            }
            throw error;
        }
    }
}

@RestControllerAdvice
class CustomerPhoneErrors {
    @ExceptionHandler(CustomerPhoneConflict.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    Map<String, String> duplicate() { return Map.of("code", "CUSTOMER_PHONE_EXISTS"); }
}
