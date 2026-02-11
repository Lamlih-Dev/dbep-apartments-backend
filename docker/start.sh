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

echo "Detecting Doctrine-mapped User table..."
USER_FULL_TABLE="$(su -s /bin/sh www-data -c "php -r '
require \"'${APP_DIR}'/vendor/autoload.php\";
$kernel = new App\Kernel(\"prod\", false);
$kernel->boot();
$em = $kernel->getContainer()->get(\"doctrine\")->getManager();
$meta = $em->getClassMetadata(App\Entity\User::class);
$schema = method_exists($meta, \"getSchemaName\") ? $meta->getSchemaName() : null;
$table = $meta->getTableName();
if (!$schema) { $schema = \"public\"; }
echo $schema.\".\".$table;
'")"

USER_SCHEMA="$(echo "$USER_FULL_TABLE" | cut -d. -f1)"
USER_TABLE="$(echo "$USER_FULL_TABLE" | cut -d. -f2)"
SEQ_NAME="${USER_TABLE}_id_seq"
PK_NAME="${USER_TABLE}_pkey"

echo "User table (Doctrine): ${USER_SCHEMA}.${USER_TABLE}"

echo "FORCING id column + default + backfill (demo bootstrap)..."
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \"
DO \\$\\$
BEGIN
  -- Ensure sequence exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind='S' AND c.relname='${SEQ_NAME}' AND n.nspname='${USER_SCHEMA}'
  ) THEN
    EXECUTE format('CREATE SEQUENCE %I.%I', '${USER_SCHEMA}', '${SEQ_NAME}');
  END IF;

  -- Add id column if missing
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='${USER_SCHEMA}' AND table_name='${USER_TABLE}' AND column_name='id'
  ) THEN
    EXECUTE format('ALTER TABLE %I.%I ADD COLUMN id INTEGER', '${USER_SCHEMA}', '${USER_TABLE}');
  END IF;

  -- Default id to nextval
  EXECUTE format(
    'ALTER TABLE %I.%I ALTER COLUMN id SET DEFAULT nextval(%L)',
    '${USER_SCHEMA}', '${USER_TABLE}', '${USER_SCHEMA}.${SEQ_NAME}'
  );

  -- Backfill existing rows
  EXECUTE format(
    'UPDATE %I.%I SET id = nextval(%L) WHERE id IS NULL',
    '${USER_SCHEMA}', '${USER_TABLE}', '${USER_SCHEMA}.${SEQ_NAME}'
  );

  -- Try NOT NULL
  BEGIN
    EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN id SET NOT NULL', '${USER_SCHEMA}', '${USER_TABLE}');
  EXCEPTION WHEN others THEN
  END;

  -- Try primary key (ignore if already exists)
  BEGIN
    EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I PRIMARY KEY (id)', '${USER_SCHEMA}', '${USER_TABLE}', '${PK_NAME}');
  EXCEPTION WHEN others THEN
  END;
END
\\$\\$;
\" " || true

echo "Ensuring unique index on email (best effort)..."
su -s /bin/sh www-data -c "${CONSOLE} doctrine:query:sql \
\"CREATE UNIQUE INDEX IF NOT EXISTS UNIQ_IDENTIFIER_EMAIL ON \\\"${USER_SCHEMA}\\\".\\\"${USER_TABLE}\\\" (email);\"" || true

echo "Creating admin user if missing..."
su -s /bin/sh www-data -c "${CONSOLE} app:user:create \"${ADMIN_EMAIL}\" \"${ADMIN_PASSWORD}\" \"${ADMIN_MODE}\"" || true

echo "Starting Apache..."
exec apache2-foreground
