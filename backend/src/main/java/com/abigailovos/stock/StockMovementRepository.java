package com.abigailovos.stock;

import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface StockMovementRepository extends JpaRepository<StockMovementEntity, String> {
    List<StockMovementEntity> findByProductIdOrderByOccurredAtAsc(String productId);

    @Query("select coalesce(sum(case when m.direction = com.abigailovos.stock.StockMovement.Direction.INCREASE then m.quantity else -m.quantity end), 0) from StockMovementEntity m where m.productId = :productId")
    BigDecimal balance(@Param("productId") String productId);
}
