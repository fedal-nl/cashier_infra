#!/bin/sh
set -eu

ENV_FILE="${ENV_FILE:-.env}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
DB_SERVICE="${DB_SERVICE:-db}"

if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"
: "${REPORTS_DB_USER:=cashier_readonly}"
: "${REPORTS_DB_PASSWORD:=cashier_readonly}"

# Creates or updates the read-only reporting role for an already-initialized DB.
docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" psql \
  --username "$DB_USER" \
  --dbname "$DB_NAME" \
  --set=readonly_user="$REPORTS_DB_USER" \
  --set=readonly_password="$REPORTS_DB_PASSWORD" \
  --set=database_name="$DB_NAME" \
  --set=ON_ERROR_STOP=1 <<'SQL'
SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L',
  :'readonly_user',
  :'readonly_password'
)
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_roles
  WHERE rolname = :'readonly_user'
)\gexec

ALTER ROLE :"readonly_user" WITH PASSWORD :'readonly_password';
GRANT CONNECT ON DATABASE :"database_name" TO :"readonly_user";
GRANT USAGE ON SCHEMA public TO :"readonly_user";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"readonly_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO :"readonly_user";
SQL
