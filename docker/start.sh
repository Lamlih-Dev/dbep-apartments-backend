#!/bin/sh
set -e

APP_DIR="/var/www/html"
CONSOLE="php ${APP_DIR}/bin/console --env=prod"

echo "Fixing permissions on var/..."
mkdir -p "${APP_DIR}/var/cache/prod" "${APP_DIR}/var/log"
chown -R www-data:www-data "${APP_DIR}/var"
chmod -R 775 "${APP_DIR}/var"

echo "DB URL is: ${DATABASE_URL:-NOT_SET}"

echo "Clearing + warming cache as www-data..."
su -s /bin/sh www-data -c "${CONSOLE} cache:clear"
su -s /bin/sh www-data -c "${CONSOLE} cache:warmup"

echo "Ensuring User table has id column (no-psql workaround)..."
# Try common user table names. Ignore failures if a table doesn't exist.
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS id SERIAL;\"" || true
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"ALTER TABLE IF EXISTS \\\"user\\\" ADD COLUMN IF NOT EXISTS id SERIAL;\"" || true
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"ALTER TABLE IF EXISTS app_user ADD COLUMN IF NOT EXISTS id SERIAL;\"" || true

echo "Ensuring primary key exists on id..."
# Add PK only if it's missing (Postgres has no IF NOT EXISTS for ADD CONSTRAINT)
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"DO \\$\\$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='users') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='users_pkey') THEN
      ALTER TABLE users ADD CONSTRAINT users_pkey PRIMARY KEY (id);
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='user_pkey') THEN
      ALTER TABLE \\\"user\\\" ADD CONSTRAINT user_pkey PRIMARY KEY (id);
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='app_user') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='app_user_pkey') THEN
      ALTER TABLE app_user ADD CONSTRAINT app_user_pkey PRIMARY KEY (id);
    END IF;
  END IF;
END
\\$\\$;\" " || true

echo "Updating DB schema as www-data..."
su -s /bin/sh www-data -c "${CONSOLE} doctrine:schema:update --force" || true

echo "Starting Apache..."
exec apache2-foreground
