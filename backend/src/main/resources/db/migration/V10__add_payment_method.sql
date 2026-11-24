-- Existing paid sales retain NULL: their original payment method is unknown.
ALTER TABLE sales ADD COLUMN payment_method VARCHAR(20) NULL;
