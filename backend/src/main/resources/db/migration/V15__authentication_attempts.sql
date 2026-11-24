-- Durable per-account attempt state. No password or login policy is changed by
-- this migration alone; the existing HTTP Basic flow does not use this table.
CREATE TABLE auth_account_attempts (
    account_id VARCHAR(36) NOT NULL PRIMARY KEY,
    window_started_at DATETIME(6) NOT NULL,
    last_attempt_at DATETIME(6) NOT NULL,
    failure_count INT NOT NULL DEFAULT 0,
    blocked_until DATETIME(6) NULL,
    CONSTRAINT fk_auth_attempt_account FOREIGN KEY (account_id)
        REFERENCES app_users(id) ON DELETE CASCADE
);
