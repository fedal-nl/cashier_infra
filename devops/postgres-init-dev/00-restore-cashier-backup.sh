#!/bin/sh
set -eu

DUMP_FILE="/docker-entrypoint-initdb.d/backup_cashier_20260705_130001.dump"

if [ ! -f "$DUMP_FILE" ]; then
  echo "Missing restore dump: $DUMP_FILE" >&2
  exit 1
fi

echo "Restoring local cashier database from $DUMP_FILE"
pg_restore \
  --verbose \
  --no-owner \
  --no-acl \
  --exit-on-error \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  "$DUMP_FILE"
