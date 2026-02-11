# ---------- build deps ----------
FROM composer:2 AS vendor
WORKDIR /app

COPY composer.json composer.lock symfony.lock* ./
RUN composer install --no-dev --prefer-dist --no-interaction --no-progress --no-scripts

# ---------- runtime ----------
FROM php:8.2-apache

# System deps + PHP extensions (Postgres)
# System deps + PHP extensions (Postgres + Intl)
RUN apt-get update && apt-get install -y \
    git unzip libpq-dev libicu-dev pkg-config \
 && docker-php-ext-install pdo pdo_pgsql intl \
 && a2enmod rewrite \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html
COPY . .
COPY --from=vendor /app/vendor /var/www/html/vendor

# Use our Apache vhost (front controller)
COPY docker/apache.conf /etc/apache2/sites-available/000-default.conf

# Symfony needs write access to var/
RUN mkdir -p var/cache var/log \
 && chown -R www-data:www-data var \
 && chmod -R 775 var

# Render provides PORT; Apache must listen on it
CMD bash -lc '\
  sed -ri "s/Listen 80/Listen ${PORT}/" /etc/apache2/ports.conf && \
  sed -ri "s/:80/:${PORT}/" /etc/apache2/sites-available/000-default.conf && \
  chmod +x /var/www/html/docker/start.sh && \
  /var/www/html/docker/start.sh'
