#!/bin/sh
set -e

echo "Fixing permissions on var/..."
mkdir -p /var/www/html/var/cache /var/www/html/var/log
chown -R www-data:www-data /var/www/html/var
chmod -R ug+rwX /var/www/html/var

echo "DB URL is: ${DATABASE_URL:-NOT_SET}"

echo "Creating/updating DB schema as www-data (temporary)..."
if ! su -s /bin/sh www-data -c "php /var/www/html/bin/console doctrine:schema:update --force --env=prod"; then
  echo "SCHEMA UPDATE FAILED (but continuing to start Apache)"
fi

echo "Starting Apache..."
exec apache2-foreground
