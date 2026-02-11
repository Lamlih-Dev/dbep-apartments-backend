#!/bin/sh
set -e

echo "Fixing permissions on var/..."
mkdir -p /var/www/html/var/cache/prod /var/www/html/var/log
chown -R www-data:www-data /var/www/html/var
chmod -R 775 /var/www/html/var

echo "DB URL is: ${DATABASE_URL:-NOT_SET}"

echo "Clearing + warming cache as www-data..."
su -s /bin/sh www-data -c "php /var/www/html/bin/console cache:clear --env=prod"
su -s /bin/sh www-data -c "php /var/www/html/bin/console cache:warmup --env=prod"

echo "Updating DB schema as www-data..."
su -s /bin/sh www-data -c "php /var/www/html/bin/console doctrine:schema:update --force --env=prod"

echo "Starting Apache..."
exec apache2-foreground
