#!/bin/sh
set -eu

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_REPLICATION_USER:?POSTGRES_REPLICATION_USER is required}"
: "${POSTGRES_REPLICATION_PASSWORD:?POSTGRES_REPLICATION_PASSWORD is required}"
: "${POSTGRES_REPLICATION_CIDRS:=samenet}"

psql \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=replication_user="$POSTGRES_REPLICATION_USER" \
  --set=replication_password="$POSTGRES_REPLICATION_PASSWORD" \
  --set=ON_ERROR_STOP=1 <<'SQL'
SELECT format(
  'CREATE ROLE %I WITH REPLICATION LOGIN PASSWORD %L',
  :'replication_user',
  :'replication_password'
)
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_roles
  WHERE rolname = :'replication_user'
)\gexec

ALTER ROLE :"replication_user"
WITH REPLICATION LOGIN PASSWORD :'replication_password';
SQL

for cidr in $(printf '%s' "$POSTGRES_REPLICATION_CIDRS" | tr ',' ' '); do
  line="host replication ${POSTGRES_REPLICATION_USER} ${cidr} scram-sha-256"
  if ! grep -Fqx "$line" "$PGDATA/pg_hba.conf"; then
    echo "$line" >> "$PGDATA/pg_hba.conf"
  fi
done
