package com.abigailovos.product;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

interface ProductRepository extends JpaRepository<Product, String> {
    List<Product> findByActiveTrue();
}
