#!/bin/sh
set -eu

: "${PGDATA:=/var/lib/postgresql/18/docker}"
: "${PRIMARY_HOST:=db}"
: "${PRIMARY_PORT:=5432}"
: "${POSTGRES_REPLICA_MAX_WAL_SENDERS:=10}"
: "${POSTGRES_REPLICA_MAX_REPLICATION_SLOTS:=10}"
: "${POSTGRES_REPLICA_WAL_KEEP_SIZE:=1024MB}"
: "${POSTGRES_REPLICATION_CIDRS:=samenet}"
: "${POSTGRES_REPLICATION_USER:?POSTGRES_REPLICATION_USER is required}"
: "${POSTGRES_REPLICATION_PASSWORD:?POSTGRES_REPLICATION_PASSWORD is required}"

if [ "$(id -u)" = "0" ]; then
  mkdir -p "$PGDATA"
  chown -R postgres:postgres /var/lib/postgresql
  exec gosu postgres "$0" "$@"
fi

export PGPASSWORD="$POSTGRES_REPLICATION_PASSWORD"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "Bootstrapping replica from ${PRIMARY_HOST}:${PRIMARY_PORT}"
  rm -rf "$PGDATA"
  mkdir -p "$PGDATA"

  until pg_isready \
    --host "$PRIMARY_HOST" \
    --port "$PRIMARY_PORT" \
    --username "$POSTGRES_REPLICATION_USER"; do
    sleep 2
  done

  pg_basebackup \
    --host "$PRIMARY_HOST" \
    --port "$PRIMARY_PORT" \
    --username "$POSTGRES_REPLICATION_USER" \
    --pgdata "$PGDATA" \
    --format plain \
    --wal-method stream \
    --write-recovery-conf \
    --progress
fi

for cidr in $(printf '%s' "$POSTGRES_REPLICATION_CIDRS" | tr ',' ' '); do
  line="host replication ${POSTGRES_REPLICATION_USER} ${cidr} scram-sha-256"
  if ! grep -Fqx "$line" "$PGDATA/pg_hba.conf"; then
    echo "$line" >> "$PGDATA/pg_hba.conf"
  fi
done

chmod 700 "$PGDATA"
exec postgres \
  -D "$PGDATA" \
  -c hot_standby=on \
  -c wal_level=replica \
  -c max_wal_senders="$POSTGRES_REPLICA_MAX_WAL_SENDERS" \
  -c max_replication_slots="$POSTGRES_REPLICA_MAX_REPLICATION_SLOTS" \
  -c wal_keep_size="$POSTGRES_REPLICA_WAL_KEEP_SIZE"
