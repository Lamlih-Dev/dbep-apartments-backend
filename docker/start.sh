#!/bin/sh
set -e

echo "Running migrations..."
php bin/console doctrine:migrations:migrate --no-interaction || true

echo "Starting Apache..."
exec apache2-foreground
