# ---------- build deps ----------
FROM composer:2 AS vendor
WORKDIR /app

COPY composer.json composer.lock symfony.lock* ./
RUN composer install --no-dev --prefer-dist --no-interaction --no-progress --no-scripts

# ---------- runtime ----------
FROM php:8.2-apache

# System deps + PHP extensions (Postgres + SQLite)
RUN apt-get update && apt-get install -y \
    git unzip libpq-dev \
 && docker-php-ext-install pdo pdo_pgsql \
 && a2enmod rewrite \
 && rm -rf /var/lib/apt/lists/*

# Allow Symfony .htaccess rewrites
RUN printf '%s\n' \
  '<Directory /var/www/html/public>' \
  '    AllowOverride All' \
  '    Require all granted' \
  '</Directory>' \
  > /etc/apache2/conf-available/symfony.conf \
 && a2enconf symfony

# Apache: set Symfony public/ as docroot
ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
 && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

WORKDIR /var/www/html
COPY . .
COPY --from=vendor /app/vendor /var/www/html/vendor

# Render provides PORT; Apache must listen on it
CMD bash -lc 'sed -ri "s/Listen 80/Listen ${PORT}/" /etc/apache2/ports.conf && sed -ri "s/:80/:${PORT}/" /etc/apache2/sites-available/000-default.conf && apache2-foreground'
