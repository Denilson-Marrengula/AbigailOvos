CREATE TABLE sales (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    request_hash VARCHAR(64) NOT NULL,
    customer_id VARCHAR(36) NOT NULL,
    seller VARCHAR(150) NOT NULL,
    delivery_status VARCHAR(20) NOT NULL,
    payment_status VARCHAR(20) NOT NULL,
    total DECIMAL(19,2) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    updated_by VARCHAR(150) NOT NULL,
    CONSTRAINT fk_sales_customer FOREIGN KEY (customer_id) REFERENCES customers(id)
);
CREATE TABLE sale_items (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    sale_id VARCHAR(36) NOT NULL,
    product_id VARCHAR(36) NOT NULL,
    product_name VARCHAR(150) NOT NULL,
    unit VARCHAR(50) NOT NULL,
    quantity DECIMAL(19,2) NOT NULL,
    unit_price DECIMAL(19,2) NOT NULL,
    CONSTRAINT fk_item_sale FOREIGN KEY (sale_id) REFERENCES sales(id),
    CONSTRAINT fk_item_product FOREIGN KEY (product_id) REFERENCES products(id)
);
CREATE INDEX idx_sale_items_product ON sale_items(product_id);
CREATE INDEX idx_sale_items_sale ON sale_items(sale_id);
