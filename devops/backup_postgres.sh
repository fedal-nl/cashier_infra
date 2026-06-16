#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.production.yml}"
DB_SERVICE="${DB_SERVICE:-db}"
APP_NAME="${APP_NAME:-cashier}"
BACKUP_DIR="${BACKUP_DIR:-backups}"
BACKUP_EXTENSION="${BACKUP_EXTENSION:-dump}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

usage() {
  cat <<EOF
Usage: ENV_FILE=.env APP_NAME=cashier BACKUP_DIR=backups $0

Environment variables:
  ENV_FILE          Path to the env file with DB_NAME, DB_USER, DB_PASSWORD, DB_PORT.
                    Default: .env
  COMPOSE_FILE      Docker Compose file to use.
                    Default: docker-compose.production.yml
  DB_SERVICE        Docker Compose Postgres service name.
                    Default: db
  APP_NAME          Prefix used in the backup filename.
                    Default: cashier
  BACKUP_DIR        Folder where backup files are written.
                    Default: backups
  BACKUP_EXTENSION  Backup file extension. Set empty for no extension.
                    Default: dump
  RETENTION_DAYS    Delete matching backup files older than this many days.
                    Default: 7
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Missing file: $file" >&2
    exit 1
  fi
}

read_env_value() {
  local key="$1"
  local file="$2"
  local line value

  line="$(
    grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file" \
      | tail -n 1 \
      || true
  )"

  if [[ -z "$line" ]]; then
    return 1
  fi

  value="${line#*=}"
  value="${value%$'\r'}"

  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi

  printf '%s' "$value"
}

require_env_value() {
  local key="$1"
  local value

  if ! value="$(read_env_value "$key" "$ENV_FILE")"; then
    echo "Missing required ${key} in ${ENV_FILE}" >&2
    exit 1
  fi

  printf '%s' "$value"
}

require_file "$ENV_FILE"
require_file "$COMPOSE_FILE"

DB_NAME="$(require_env_value DB_NAME)"
DB_USER="$(require_env_value DB_USER)"
DB_PASSWORD="$(require_env_value DB_PASSWORD)"
DB_PORT="$(read_env_value DB_PORT "$ENV_FILE" || printf '5432')"

mkdir -p "$BACKUP_DIR"

DATETIME="$(date +"%Y%m%d_%H%M%S")"
BACKUP_BASENAME="${APP_NAME}_backup_${DATETIME}"
if [[ -n "$BACKUP_EXTENSION" ]]; then
  BACKUP_FILE="${BACKUP_DIR}/${BACKUP_BASENAME}.${BACKUP_EXTENSION}"
else
  BACKUP_FILE="${BACKUP_DIR}/${BACKUP_BASENAME}"
fi

# Run pg_dump inside the Postgres container. From inside that container the
# database is available on localhost, even when DB_HOST=db is used by Django.
DATABASE_URL="postgresql://${DB_USER}@localhost:${DB_PORT}/${DB_NAME}"

echo "Creating backup: ${BACKUP_FILE}"

docker compose -f "$COMPOSE_FILE" exec -T \
  -e PGPASSWORD="$DB_PASSWORD" \
  "$DB_SERVICE" \
  pg_dump \
    --dbname="$DATABASE_URL" \
    --format=custom \
    --no-owner \
    --no-acl \
  > "$BACKUP_FILE"

echo "Backup created: ${BACKUP_FILE}"

if [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
  echo "Deleting ${APP_NAME} backups older than ${RETENTION_DAYS} days from ${BACKUP_DIR}"
  find "$BACKUP_DIR" \
    -maxdepth 1 \
    -type f \
    -name "${APP_NAME}_backup_*" \
    -mtime "+${RETENTION_DAYS}" \
    -delete
else
  echo "RETENTION_DAYS must be a positive number, got: ${RETENTION_DAYS}" >&2
  exit 1
fi
