# ---------- build deps ----------
FROM composer:2 AS vendor
WORKDIR /app

COPY composer.json composer.lock symfony.lock* ./
RUN composer install --no-dev --prefer-dist --no-interaction --no-progress --no-scripts

# ---------- runtime ----------
FROM php:8.2-apache

# System deps + PHP extensions (Postgres)
RUN apt-get update && apt-get install -y \
    git unzip libpq-dev \
 && docker-php-ext-install pdo pdo_pgsql \
 && a2enmod rewrite \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html
COPY . .
COPY --from=vendor /app/vendor /var/www/html/vendor

# Use our Apache vhost (front controller)
COPY docker/apache.conf /etc/apache2/sites-available/000-default.conf

# Render provides PORT; Apache must listen on it
CMD bash -lc 'sed -ri "s/Listen 80/Listen ${PORT}/" /etc/apache2/ports.conf \
 && sed -ri "s/:80/:${PORT}/" /etc/apache2/sites-available/000-default.conf \
 && apache2-foreground'
