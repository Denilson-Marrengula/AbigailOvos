-- Existing credentials are not changed or expired during migration.
ALTER TABLE app_users ADD COLUMN must_change_password BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE app_users ADD COLUMN temporary_password_expires_at DATETIME(6) NULL;
