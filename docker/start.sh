#!/bin/sh
set -e

APP_DIR="/var/www/html"
CONSOLE="php ${APP_DIR}/bin/console --env=prod"

# Seed admin (set these as Render env vars!)
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-StrongPassw0rd}"
ADMIN_MODE="${ADMIN_MODE:-admin}"   # <- important: your command expects "admin" or "user"

echo "Fixing permissions on var/..."
mkdir -p "${APP_DIR}/var/cache/prod" "${APP_DIR}/var/log"
chown -R www-data:www-data "${APP_DIR}/var"
chmod -R 775 "${APP_DIR}/var"

echo "DB URL is: ${DATABASE_URL:-NOT_SET}"

echo "Clearing + warming cache as www-data..."
su -s /bin/sh www-data -c "${CONSOLE} cache:clear"
su -s /bin/sh www-data -c "${CONSOLE} cache:warmup"

echo "Detecting user table(s) by columns (email, roles, password) across ALL schemas..."
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"
SELECT table_schema, table_name
FROM information_schema.columns
WHERE table_schema NOT IN ('pg_catalog','information_schema')
GROUP BY table_schema, table_name
HAVING
  SUM(CASE WHEN column_name='email' THEN 1 ELSE 0 END) > 0
  AND SUM(CASE WHEN column_name='roles' THEN 1 ELSE 0 END) > 0
  AND SUM(CASE WHEN column_name='password' THEN 1 ELSE 0 END) > 0
ORDER BY table_schema, table_name;
\"" || true

echo "Ensuring id column exists on any matching user table..."
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"
DO \\$\\$
DECLARE t record;
BEGIN
  FOR t IN
    SELECT table_schema, table_name
    FROM information_schema.columns
    WHERE table_schema NOT IN ('pg_catalog','information_schema')
    GROUP BY table_schema, table_name
    HAVING
      SUM(CASE WHEN column_name='email' THEN 1 ELSE 0 END) > 0
      AND SUM(CASE WHEN column_name='roles' THEN 1 ELSE 0 END) > 0
      AND SUM(CASE WHEN column_name='password' THEN 1 ELSE 0 END) > 0
  LOOP
    EXECUTE format('ALTER TABLE %I.%I ADD COLUMN IF NOT EXISTS id SERIAL', t.table_schema, t.table_name);
  END LOOP;
END
\\$\\$;
\"" || true

echo "Ensuring primary key exists on (id) for any matching user table..."
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"
DO \\$\\$
DECLARE t record;
DECLARE pkname text;
BEGIN
  FOR t IN
    SELECT table_schema, table_name
    FROM information_schema.columns
    WHERE table_schema NOT IN ('pg_catalog','information_schema')
    GROUP BY table_schema, table_name
    HAVING
      SUM(CASE WHEN column_name='email' THEN 1 ELSE 0 END) > 0
      AND SUM(CASE WHEN column_name='roles' THEN 1 ELSE 0 END) > 0
      AND SUM(CASE WHEN column_name='password' THEN 1 ELSE 0 END) > 0
  LOOP
    pkname := t.table_name || '_pkey';

    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint c
      JOIN pg_class r ON r.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = r.relnamespace
      WHERE c.contype='p'
        AND c.conname = pkname
        AND n.nspname = t.table_schema
        AND r.relname = t.table_name
    ) THEN
      BEGIN
        EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I PRIMARY KEY (id)', t.table_schema, t.table_name, pkname);
      EXCEPTION WHEN others THEN
        RAISE NOTICE 'Could not add PK on %.%.id (maybe another PK exists): %', t.table_schema, t.table_name, SQLERRM;
      END;
    END IF;
  END LOOP;
END
\\$\\$;
\"" || true

echo "Updating DB schema as www-data..."
su -s /bin/sh www-data -c "${CONSOLE} doctrine:schema:update --force" || true

echo "Creating admin user if missing..."
su -s /bin/sh www-data -c "${CONSOLE} app:user:create \"${ADMIN_EMAIL}\" \"${ADMIN_PASSWORD}\" \"${ADMIN_MODE}\"" || true

echo "Starting Apache..."
exec apache2-foreground
