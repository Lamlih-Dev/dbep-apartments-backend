#!/bin/sh
set -e

APP_DIR="/var/www/html"
CONSOLE="php ${APP_DIR}/bin/console --env=prod"

ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-StrongPassw0rd}"
ADMIN_MODE="${ADMIN_MODE:-admin}"   # "admin" or "user"

echo "Fixing permissions on var/..."
mkdir -p "${APP_DIR}/var/cache/prod" "${APP_DIR}/var/log"
chown -R www-data:www-data "${APP_DIR}/var"
chmod -R 775 "${APP_DIR}/var"

echo "DB URL is: ${DATABASE_URL:-NOT_SET}"

echo "Clearing + warming cache as www-data..."
su -s /bin/sh www-data -c "${CONSOLE} cache:clear"
su -s /bin/sh www-data -c "${CONSOLE} cache:warmup"

echo "Bootstrapping DB (demo): ensure user table exists (Postgres)..."
# NOTE: "user" is a reserved-ish word -> always quote it
# roles stored as JSON (works well with Doctrine array mapping for Postgres)
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \
\"CREATE TABLE IF NOT EXISTS \\\"user\\\" (
  id SERIAL PRIMARY KEY,
  email VARCHAR(180) NOT NULL,
  roles JSON NOT NULL,
  password VARCHAR(255) NOT NULL
);\"" || true

echo "Ensuring unique index on email..."
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \
\"CREATE UNIQUE INDEX IF NOT EXISTS UNIQ_IDENTIFIER_EMAIL ON \\\"user\\\" (email);\"" || true

echo "Creating admin user if missing..."
# Your command checks for existing user, so it's safe to run every boot
su -s /bin/sh www-data -c "${CONSOLE} app:user:create \"${ADMIN_EMAIL}\" \"${ADMIN_PASSWORD}\" \"${ADMIN_MODE}\"" || true

echo "Starting Apache..."
exec apache2-foreground
