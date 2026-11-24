-- Do not infer historical event dates from the last update: it may describe
-- another action. Existing records remain NULL and are reported separately.
ALTER TABLE products ADD COLUMN minimum_stock DECIMAL(19,2) NULL;
ALTER TABLE sales ADD COLUMN delivered_at DATETIME(6) NULL;
ALTER TABLE sales ADD COLUMN paid_at DATETIME(6) NULL;
ALTER TABLE sales ADD COLUMN cancelled_at DATETIME(6) NULL;
