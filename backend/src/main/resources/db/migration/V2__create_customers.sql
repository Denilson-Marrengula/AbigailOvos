CREATE TABLE customers (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(40),
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL
);
