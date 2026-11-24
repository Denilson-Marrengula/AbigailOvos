-- No existing account credentials are changed. Sessions are introduced disabled
-- until the authentication flow is explicitly integrated and validated.
ALTER TABLE app_users ADD COLUMN session_epoch BIGINT NOT NULL DEFAULT 0;

CREATE TABLE auth_sessions (
    token_hash VARCHAR(64) NOT NULL PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL,
    account_epoch BIGINT NOT NULL,
    created_at DATETIME(6) NOT NULL,
    last_seen_at DATETIME(6) NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    revoked_at DATETIME(6) NULL,
    CONSTRAINT fk_auth_session_account FOREIGN KEY (account_id) REFERENCES app_users(id) ON DELETE CASCADE
);
CREATE INDEX idx_auth_sessions_account ON auth_sessions(account_id);
