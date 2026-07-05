#!/bin/sh
set -eu

if [ -z "${ENV_FILE:-}" ]; then
  ENV_FILE=".env"
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

if [ -z "${COMPOSE_FILE:-}" ]; then
  COMPOSE_FILE="docker-compose.yml"
fi

DB_SERVICE="${DB_SERVICE:-db}"

load_env_value() {
  key="$1"
  current_value="$(eval "printf '%s' \"\${$key:-}\"")"

  if [ -n "$current_value" ]; then
    return
  fi

  value="$(
    grep -E "^${key}=" "$ENV_FILE" \
      | tail -n 1 \
      | sed "s/^${key}=//" \
      | sed "s/^'//; s/'$//; s/^\"//; s/\"$//"
  )"

  if [ -n "$value" ]; then
    export "$key=$value"
  fi
}

load_env_value DB_NAME
load_env_value DB_USER
load_env_value REPORTS_DB_NAME
load_env_value REPORTS_DB_USER
load_env_value REPORTS_DB_PASSWORD

: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"
: "${REPORTS_DB_NAME:?REPORTS_DB_NAME is required}"
: "${REPORTS_DB_USER:?REPORTS_DB_USER is required}"
: "${REPORTS_DB_PASSWORD:?REPORTS_DB_PASSWORD is required}"

echo "Using env file: $ENV_FILE"
echo "Using compose file: $COMPOSE_FILE"
echo "Creating local ETL database '$REPORTS_DB_NAME' and user '$REPORTS_DB_USER'"

docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" psql \
  --username "$DB_USER" \
  --dbname "$DB_NAME" \
  --set=etl_database="$REPORTS_DB_NAME" \
  --set=etl_user="$REPORTS_DB_USER" \
  --set=etl_password="$REPORTS_DB_PASSWORD" \
  --set=ON_ERROR_STOP=1 <<'SQL'
SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L',
  :'etl_user',
  :'etl_password'
)
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_roles
  WHERE rolname = :'etl_user'
)\gexec

ALTER ROLE :"etl_user" WITH PASSWORD :'etl_password';

SELECT format(
  'CREATE DATABASE %I OWNER %I',
  :'etl_database',
  :'etl_user'
)
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_database
  WHERE datname = :'etl_database'
)\gexec

SELECT format(
  'ALTER DATABASE %I OWNER TO %I',
  :'etl_database',
  :'etl_user'
)\gexec

GRANT ALL PRIVILEGES ON DATABASE :"etl_database" TO :"etl_user";

\connect :"etl_database"

ALTER SCHEMA public OWNER TO :"etl_user";
GRANT ALL PRIVILEGES ON SCHEMA public TO :"etl_user";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO :"etl_user";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO :"etl_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON TABLES TO :"etl_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON SEQUENCES TO :"etl_user";
SQL

echo "Local ETL database setup completed."

echo "Verifying ETL user can create tables in '$REPORTS_DB_NAME'"
docker compose -f "$COMPOSE_FILE" exec -T \
  -e PGPASSWORD="$REPORTS_DB_PASSWORD" \
  "$DB_SERVICE" psql \
  --host localhost \
  --username "$REPORTS_DB_USER" \
  --dbname "$REPORTS_DB_NAME" \
  --set=ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS public.__etl_permission_check (
  id integer PRIMARY KEY
);
DROP TABLE public.__etl_permission_check;
SQL

echo "ETL database permissions verified."
