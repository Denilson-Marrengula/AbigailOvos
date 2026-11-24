-- Introduces storage only. This migration does not enable MFA or alter passwords.
CREATE TABLE admin_authenticators (
    account_id VARCHAR(36) NOT NULL PRIMARY KEY,
    active_secret VARCHAR(192) NULL,
    pending_secret VARCHAR(192) NULL,
    pending_id VARCHAR(36) NULL,
    pending_started_at DATETIME(6) NULL,
    pending_expires_at DATETIME(6) NULL,
    not_before DATETIME(6) NULL,
    last_accepted_step BIGINT NOT NULL DEFAULT -1,
    CONSTRAINT fk_admin_authenticator_account FOREIGN KEY (account_id)
        REFERENCES app_users(id) ON DELETE CASCADE
);
