#!/bin/sh
set -e

APP_DIR="/var/www/html"
CONSOLE="php ${APP_DIR}/bin/console --env=prod"

echo "Fixing permissions on var/..."
mkdir -p "${APP_DIR}/var/cache/prod" "${APP_DIR}/var/log"
chown -R www-data:www-data "${APP_DIR}/var"
chmod -R ug+rwX "${APP_DIR}/var"

echo "DB URL is: ${DATABASE_URL:-NOT_SET}"

echo "Clearing + warming cache as www-data..."
su -s /bin/sh www-data -c "${CONSOLE} cache:clear" || true
su -s /bin/sh www-data -c "${CONSOLE} cache:warmup" || true

echo "Updating DB schema as www-data (demo mode)..."
# This will create/update tables based on your Doctrine metadata (works without migrations)
su -s /bin/sh www-data -c "${CONSOLE} doctrine:schema:update --force" || true

# Optional: create an admin user if env vars are set
# (ONLY runs if ADMIN_EMAIL and ADMIN_PASSWORD are provided)
if [ -n "${ADMIN_EMAIL}" ] && [ -n "${ADMIN_PASSWORD}" ]; then
  echo "Seeding admin user (if command exists)..."
  su -s /bin/sh www-data -c "${CONSOLE} app:user:create \"${ADMIN_EMAIL}\" \"${ADMIN_PASSWORD}\" \"${ADMIN_MODE:-admin}\"" || true
else
  echo "Admin seed skipped (ADMIN_EMAIL / ADMIN_PASSWORD not set)."
fi

echo "Starting Apache..."
exec apache2-foreground
