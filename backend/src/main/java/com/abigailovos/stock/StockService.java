package com.abigailovos.stock;

import com.abigailovos.product.Product;
import com.abigailovos.audit.AuditLog;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import java.math.BigDecimal;
import java.time.Instant;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import static org.springframework.http.HttpStatus.*;

@Service
public class StockService {
    private final EntityManager entityManager;
    private final StockMovementRepository movements;
    private final AuditLog audit;

    StockService(EntityManager entityManager, StockMovementRepository movements, AuditLog audit) {
        this.entityManager = entityManager; this.movements = movements; this.audit = audit;
    }

    @Transactional(isolation = org.springframework.transaction.annotation.Isolation.READ_COMMITTED)
    StockMovementEntity create(UUID operationId, UUID productId, StockMovement.Type type, StockMovement.Direction direction,
                               BigDecimal quantity, String reason, String actor) {
        if (actor == null || actor.isBlank() || actor.length() > 150) {
            throw new ResponseStatusException(FORBIDDEN, "Utilizador inválido");
        }
        // Serializes all balance-changing movements for this product in the database.
        Product product = lockProduct(productId.toString());
        var previous = movements.findById(operationId.toString());
        if (previous.isPresent()) {
            StockMovementEntity saved = previous.get();
            if (!saved.getProductId().equals(productId.toString()) || !saved.getAdministrator().equals(actor)
                    || saved.getType() != type || saved.getDirection() != direction
                    || saved.getQuantity().compareTo(quantity) != 0 || !saved.getReason().equals(reason.strip())) {
                throw new ResponseStatusException(CONFLICT, "Identificador já utilizado");
            }
            return saved;
        }
        if (!product.isActive()) throw new ResponseStatusException(NOT_FOUND, "Produto não encontrado");
        try {
            // The authenticated username is persisted as the actor until real user IDs exist.
            UUID actorReference = UUID.nameUUIDFromBytes(actor.getBytes(StandardCharsets.UTF_8));
            StockMovement movement = new StockMovement(operationId, productId, actorReference,
                    type, quantity, direction, reason, Instant.now());
            movement.applyTo(available(productId.toString()));
            StockMovementEntity saved = movements.save(new StockMovementEntity(movement, actor));
            audit.record(actor, "STOCK_MOVEMENT_CREATED", "STOCK_MOVEMENT", saved.getId(),
                    "type=" + type + ";direction=" + direction);
            return saved;
        } catch (IllegalArgumentException ex) {
            throw new ResponseStatusException(BAD_REQUEST, ex.getMessage());
        }
    }

    public Product lockProduct(String id) {
        Product product = entityManager.find(Product.class, id, LockModeType.PESSIMISTIC_WRITE);
        if (product == null) throw new ResponseStatusException(NOT_FOUND, "Produto não encontrado");
        return product;
    }

    public BigDecimal reserved(String productId) {
        return entityManager.createQuery("select coalesce(sum(i.quantity), 0) from SaleItem i, Sale s where i.saleId = s.id and i.productId = :id and s.deliveryStatus = :status", BigDecimal.class)
                .setParameter("id", productId).setParameter("status", com.abigailovos.sales.Sale.Delivery.PENDING).getSingleResult();
    }

    public BigDecimal physical(String productId) { return movements.balance(productId); }
    public BigDecimal available(String productId) { return physical(productId).subtract(reserved(productId)); }

    public void saleExit(String productId, BigDecimal quantity, String actor, String saleId) {
        StockMovement movement = new StockMovement(UUID.randomUUID(), UUID.fromString(productId), UUID.nameUUIDFromBytes(actor.getBytes(StandardCharsets.UTF_8)),
                StockMovement.Type.SALE, quantity, StockMovement.Direction.DECREASE, "Venda " + saleId, Instant.now());
        movement.applyTo(available(productId));
        movements.save(new StockMovementEntity(movement, actor));
    }

    @Transactional(readOnly = true)
    BigDecimal balance(UUID productId, boolean includeInactive) {
        Product product = entityManager.find(Product.class, productId.toString());
        if (product == null || (!includeInactive && !product.isActive())) {
            throw new ResponseStatusException(NOT_FOUND, "Produto não encontrado");
        }
        return movements.balance(productId.toString());
    }

    @Transactional(readOnly = true)
    List<StockMovementEntity> history(UUID productId) {
        if (entityManager.find(Product.class, productId.toString()) == null) {
            throw new ResponseStatusException(NOT_FOUND, "Produto não encontrado");
        }
        return movements.findByProductIdOrderByOccurredAtAsc(productId.toString());
    }
}
