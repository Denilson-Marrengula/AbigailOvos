CREATE TABLE reserved_usernames (
    username_key VARCHAR(100) NOT NULL PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL,
    reserved_at DATETIME(6) NOT NULL
);

-- Fail instead of merging accounts if an existing database has case-colliding names.
INSERT INTO reserved_usernames (username_key, account_id, reserved_at)
SELECT LOWER(username), id, created_at FROM app_users;
