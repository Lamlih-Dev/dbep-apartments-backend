#!/bin/sh
set -e

echo "Fixing permissions on var/..."
mkdir -p /var/www/html/var/cache /var/www/html/var/log
chown -R www-data:www-data /var/www/html/var
chmod -R ug+rwX /var/www/html/var

echo "Running migrations as www-data..."
su -s /bin/sh www-data -c "php /var/www/html/bin/console doctrine:migrations:migrate --no-interaction" || true

echo "Clearing cache as www-data..."
su -s /bin/sh www-data -c "php /var/www/html/bin/console cache:clear --env=prod" || true

echo "Starting Apache..."
exec apache2-foreground
