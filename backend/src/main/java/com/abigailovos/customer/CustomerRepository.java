package com.abigailovos.customer;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface CustomerRepository extends JpaRepository<Customer, String> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from Customer c where c.id = :id")
    Optional<Customer> findForUpdate(@Param("id") String id);
}
