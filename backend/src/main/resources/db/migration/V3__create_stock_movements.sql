CREATE TABLE stock_movements (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    product_id VARCHAR(36) NOT NULL,
    administrator VARCHAR(150) NOT NULL,
    movement_type VARCHAR(20) NOT NULL,
    direction VARCHAR(10) NOT NULL,
    quantity DECIMAL(19, 2) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    occurred_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_stock_product FOREIGN KEY (product_id) REFERENCES products(id)
);
CREATE INDEX idx_stock_product ON stock_movements(product_id);
