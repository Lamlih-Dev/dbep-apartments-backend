#!/bin/sh
set -e

APP_DIR="/var/www/html"
CONSOLE="php ${APP_DIR}/bin/console --env=prod"

echo "Fixing permissions on var/..."
mkdir -p "${APP_DIR}/var/cache/prod" "${APP_DIR}/var/log"
chown -R www-data:www-data "${APP_DIR}/var"
chmod -R ug+rwX "${APP_DIR}/var"

echo "DB URL is: ${DATABASE_URL:-NOT_SET}"

echo "Clearing + warming cache..."
su -s /bin/sh www-data -c "${CONSOLE} cache:clear" || true
su -s /bin/sh www-data -c "${CONSOLE} cache:warmup" || true

echo "NUCLEAR DEMO RESET: drop + recreate users table (email PK)..."
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"
DROP TABLE IF EXISTS users;
CREATE TABLE users (
  email VARCHAR(180) PRIMARY KEY,
  roles JSON NOT NULL,
  password VARCHAR(255) NOT NULL
);
\" " || true

if [ -n "${ADMIN_EMAIL}" ] && [ -n "${ADMIN_PASSWORD}" ]; then
  echo "Seeding admin user..."
  su -s /bin/sh www-data -c "${CONSOLE} app:user:create \"${ADMIN_EMAIL}\" \"${ADMIN_PASSWORD}\" \"${ADMIN_MODE:-admin}\"" || true
else
  echo "Admin seed skipped (set ADMIN_EMAIL and ADMIN_PASSWORD to auto-create)."
fi

echo "Starting Apache..."
exec apache2-foreground
