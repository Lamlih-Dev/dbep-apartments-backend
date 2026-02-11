#!/bin/sh
set -e

APP_DIR="/var/www/html"
CONSOLE="php ${APP_DIR}/bin/console --env=prod"

ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-StrongPassw0rd}"
ADMIN_MODE="${ADMIN_MODE:-admin}"   # "admin" or "user"

echo "Fixing permissions on var/..."
mkdir -p "${APP_DIR}/var/cache/prod" "${APP_DIR}/var/log"
chown -R www-data:www-data "${APP_DIR}/var"
chmod -R 775 "${APP_DIR}/var"

echo "DB URL is: ${DATABASE_URL:-NOT_SET}"

echo "Clearing + warming cache as www-data..."
su -s /bin/sh www-data -c "${CONSOLE} cache:clear" || true
su -s /bin/sh www-data -c "${CONSOLE} cache:warmup" || true

echo "FORCE FIX: add/backfill id on any table that has email+password (all schemas)..."
# This catches the User table even if it's not named "user" and even if schema != public.
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"
DO \\$\\$
DECLARE t record;
DECLARE seq_name text;
DECLARE pk_name text;
BEGIN
  FOR t IN
    SELECT table_schema, table_name
    FROM information_schema.columns
    WHERE table_schema NOT IN ('pg_catalog','information_schema')
    GROUP BY table_schema, table_name
    HAVING
      SUM(CASE WHEN column_name='email' THEN 1 ELSE 0 END) > 0
      AND SUM(CASE WHEN column_name='password' THEN 1 ELSE 0 END) > 0
  LOOP
    seq_name := t.table_name || '_id_seq';
    pk_name  := t.table_name || '_pkey';

    -- ensure sequence exists
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE c.relkind='S' AND c.relname=seq_name AND n.nspname=t.table_schema
    ) THEN
      EXECUTE format('CREATE SEQUENCE %I.%I', t.table_schema, seq_name);
    END IF;

    -- add id column if missing
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema=t.table_schema AND table_name=t.table_name AND column_name='id'
    ) THEN
      EXECUTE format('ALTER TABLE %I.%I ADD COLUMN id INTEGER', t.table_schema, t.table_name);
    END IF;

    -- set default nextval
    EXECUTE format(
      'ALTER TABLE %I.%I ALTER COLUMN id SET DEFAULT nextval(%L)',
      t.table_schema, t.table_name, t.table_schema||'.'||seq_name
    );

    -- backfill null ids
    EXECUTE format(
      'UPDATE %I.%I SET id = nextval(%L) WHERE id IS NULL',
      t.table_schema, t.table_name, t.table_schema||'.'||seq_name
    );

    -- try set NOT NULL (ignore failures)
    BEGIN
      EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN id SET NOT NULL', t.table_schema, t.table_name);
    EXCEPTION WHEN others THEN
    END;

    -- try add PK (ignore failures if PK already exists / different PK exists)
    BEGIN
      EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I PRIMARY KEY (id)', t.table_schema, t.table_name, pk_name);
    EXCEPTION WHEN others THEN
    END;

    -- try unique index on email (ignore failures)
    BEGIN
      EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS %I ON %I.%I (email)', 'uniq_'||t.table_name||'_email', t.table_schema, t.table_name);
    EXCEPTION WHEN others THEN
    END;

  END LOOP;
END
\\$\\$;
\" " || true

echo "Creating admin user if missing..."
su -s /bin/sh www-data -c "${CONSOLE} app:user:create \"${ADMIN_EMAIL}\" \"${ADMIN_PASSWORD}\" \"${ADMIN_MODE}\"" || true

echo "Starting Apache..."
exec apache2-foreground
