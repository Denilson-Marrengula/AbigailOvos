package com.abigailovos.customer;

import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@RestController
@RequestMapping("/api/customers")
class CustomerController {
    private final CustomerRepository customers;

    CustomerController(CustomerRepository customers) {
        this.customers = customers;
    }

    @GetMapping
    List<Customer> list() {
        return customers.findAll();
    }

    @GetMapping("/{id}")
    Customer get(@PathVariable String id) {
        return customers.findById(id).orElseThrow(() -> new ResponseStatusException(NOT_FOUND));
    }

}
