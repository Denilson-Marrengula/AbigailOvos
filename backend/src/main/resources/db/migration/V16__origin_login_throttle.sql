-- Experimental storage only. It does not enable or protect the current Basic login.
CREATE TABLE auth_origin_throttle_meta (
    id VARCHAR(16) NOT NULL PRIMARY KEY,
    entry_count INT NOT NULL,
    last_observed_at DATETIME(6) NULL,
    last_pruned_at DATETIME(6) NULL
);
INSERT INTO auth_origin_throttle_meta (id, entry_count) VALUES ('global', 0);

CREATE TABLE auth_origin_attempts (
    origin_hash VARCHAR(64) NOT NULL PRIMARY KEY,
    window_started_at DATETIME(6) NOT NULL,
    last_request_at DATETIME(6) NOT NULL,
    request_count INT NOT NULL
);
CREATE INDEX idx_auth_origin_last_request ON auth_origin_attempts(last_request_at);
