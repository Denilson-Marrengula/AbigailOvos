package com.abigailovos.customer;

import java.util.List;
import java.security.Principal;
import com.abigailovos.audit.AuditLog;
import jakarta.validation.Valid;
import jakarta.persistence.EntityManager;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.transaction.annotation.Transactional;
import static org.springframework.http.HttpStatus.NOT_FOUND;
import static org.springframework.http.HttpStatus.BAD_REQUEST;

@RestController
@RequestMapping("/api/customers")
class CustomerController {
    private final CustomerRepository customers;
    private final AuditLog audit;
    private final EntityManager em;

    CustomerController(CustomerRepository customers, AuditLog audit, EntityManager em) {
        this.customers = customers;
        this.audit = audit;
        this.em = em;
    }

    record UpdateCustomer(@NotBlank @Size(max = 150) String name,
            @Size(max = 40) String phone) {}

    @GetMapping
    List<Customer> list() {
        return customers.findAll();
    }

    @GetMapping("/{id}")
    Customer get(@PathVariable String id) {
        return customers.findById(id).orElseThrow(() -> new ResponseStatusException(NOT_FOUND));
    }

    @PutMapping("/{id}")
    @Transactional
    Customer update(@PathVariable String id, @Valid @RequestBody UpdateCustomer request, Principal principal) {
        Customer customer = customers.findForUpdate(id).orElseThrow(() -> new ResponseStatusException(NOT_FOUND));
        try {
            customer.update(request.name(), request.phone());
        } catch (IllegalArgumentException ex) {
            throw new ResponseStatusException(BAD_REQUEST, "Telefone obrigatório ou inválido");
        }
        CustomerPhoneConflict.flushCustomer(em);
        audit.record(principal.getName(), "CUSTOMER_UPDATED", "CUSTOMER", customer.getId(), "fields=name,phone");
        return customer;
    }
}
