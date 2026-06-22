#!/bin/sh
set -eu

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${REPORTS_DB_USER:=cashier_readonly}"
: "${REPORTS_DB_PASSWORD:=cashier_readonly}"

psql \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=readonly_user="$REPORTS_DB_USER" \
  --set=readonly_password="$REPORTS_DB_PASSWORD" \
  --set=database_name="$POSTGRES_DB" \
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

GRANT CONNECT ON DATABASE :"database_name" TO :"readonly_user";
GRANT USAGE ON SCHEMA public TO :"readonly_user";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"readonly_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO :"readonly_user";
SQL
