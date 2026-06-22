#!/bin/sh
set -eu

if [ -z "${ENV_FILE:-}" ]; then
  if [ -f ".env" ]; then
    ENV_FILE=".env"
  else
    echo "No .env file found. Set ENV_FILE=/path/to/env-file." >&2
    exit 1
  fi
elif [ ! -f "$ENV_FILE" ]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

if [ -z "${COMPOSE_FILE:-}" ]; then
  if [ -f "docker-compose.yml" ]; then
    COMPOSE_FILE="docker-compose.yml"
  elif [ -f "docker-compose.production.yml" ]; then
    COMPOSE_FILE="docker-compose.production.yml"
  else
    echo "No docker compose file found. Set COMPOSE_FILE=/path/to/compose.yml." >&2
    exit 1
  fi
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
      | sed "s/^${key}=//"
  )"

  if [ -n "$value" ]; then
    export "$key=$value"
  fi
}

load_env_value DB_NAME
load_env_value DB_USER
load_env_value REPORTS_DB_USER
load_env_value REPORTS_DB_PASSWORD

: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"
: "${REPORTS_DB_USER:=cashier_readonly}"
: "${REPORTS_DB_PASSWORD:=cashier_readonly}"

# Creates or updates the read-only reporting role for an already-initialized DB.
echo "Using env file: $ENV_FILE"
echo "Using compose file: $COMPOSE_FILE"
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
