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

# --- JWT KEYS FIX FOR RENDER ---
echo "Preparing JWT keys..."
mkdir -p "${APP_DIR}/config/jwt"

# If Render secret files exist, copy them to a readable location
if [ -f /etc/secrets/private.pem ] && [ -f /etc/secrets/public.pem ]; then
  echo "Copying JWT keys from /etc/secrets -> config/jwt"
  cp /etc/secrets/private.pem "${APP_DIR}/config/jwt/private.pem"
  cp /etc/secrets/public.pem  "${APP_DIR}/config/jwt/public.pem"
fi

# Ensure readable by www-data (Lexik needs private key readable)
chown -R www-data:www-data "${APP_DIR}/config/jwt" || true
chmod 600 "${APP_DIR}/config/jwt/private.pem" || true
chmod 644 "${APP_DIR}/config/jwt/public.pem"  || true

# Force Lexik to use the copied keys (overrides Render env paths)
export JWT_SECRET_KEY="${APP_DIR}/config/jwt/private.pem"
export JWT_PUBLIC_KEY="${APP_DIR}/config/jwt/public.pem"
export JWT_PASSPHRASE="${JWT_PASSPHRASE:-}"

echo "Starting Apache..."
exec apache2-foreground
