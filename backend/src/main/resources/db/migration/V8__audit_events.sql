CREATE TABLE audit_events (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    actor VARCHAR(150) NOT NULL,
    action VARCHAR(50) NOT NULL,
    target_type VARCHAR(30) NOT NULL,
    target_id VARCHAR(36) NOT NULL,
    detail VARCHAR(255) NOT NULL,
    occurred_at DATETIME(6) NOT NULL
);
CREATE INDEX idx_audit_occurred_id ON audit_events(occurred_at, id);
