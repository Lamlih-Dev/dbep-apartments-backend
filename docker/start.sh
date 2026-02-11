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

echo "Detecting user table(s) by columns (email, roles, password)..."
# Prints matching table(s). Usually only one.
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"
SELECT table_name
FROM information_schema.columns
WHERE table_schema='public'
GROUP BY table_name
HAVING
  SUM(CASE WHEN column_name='email' THEN 1 ELSE 0 END) > 0
  AND SUM(CASE WHEN column_name='roles' THEN 1 ELSE 0 END) > 0
  AND SUM(CASE WHEN column_name='password' THEN 1 ELSE 0 END) > 0
ORDER BY table_name;
\"" || true

echo "Ensuring id column exists on any table that looks like the user table..."
# Add id to ALL matching tables (safe + idempotent)
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"
DO \\$\\$
DECLARE t record;
BEGIN
  FOR t IN
    SELECT table_name
    FROM information_schema.columns
    WHERE table_schema='public'
    GROUP BY table_name
    HAVING
      SUM(CASE WHEN column_name='email' THEN 1 ELSE 0 END) > 0
      AND SUM(CASE WHEN column_name='roles' THEN 1 ELSE 0 END) > 0
      AND SUM(CASE WHEN column_name='password' THEN 1 ELSE 0 END) > 0
  LOOP
    EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS id SERIAL', t.table_name);
  END LOOP;
END
\\$\\$;
\"" || true

echo "Ensuring a primary key exists on (id) for any matching user table..."
# Add PK if missing. If an old PK exists (e.g. on email), this might fail — we don't crash the service.
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"
DO \\$\\$
DECLARE t record;
DECLARE pkname text;
BEGIN
  FOR t IN
    SELECT table_name
    FROM information_schema.columns
    WHERE table_schema='public'
    GROUP BY table_name
    HAVING
      SUM(CASE WHEN column_name='email' THEN 1 ELSE 0 END) > 0
      AND SUM(CASE WHEN column_name='roles' THEN 1 ELSE 0 END) > 0
      AND SUM(CASE WHEN column_name='password' THEN 1 ELSE 0 END) > 0
  LOOP
    pkname := t.table_name || '_pkey';

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = pkname) THEN
      BEGIN
        EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I PRIMARY KEY (id)', t.table_name, pkname);
      EXCEPTION WHEN others THEN
        -- Don't fail deploy if table already has a different PK
        RAISE NOTICE 'Could not add PK on %.id (maybe PK already exists): %', t.table_name, SQLERRM;
      END;
    END IF;
  END LOOP;
END
\\$\\$;
\"" || true

echo "Updating DB schema as www-data..."
su -s /bin/sh www-data -c "${CONSOLE} doctrine:schema:update --force" || true

echo "Creating admin user if missing..."
su -s /bin/sh www-data -c "${CONSOLE} app:user:create" || true

echo "Starting Apache..."
exec apache2-foreground
