#!/usr/bin/env bash
set -euo pipefail

data_dir=/var/lib/postgresql/data/pgdata
if [ -f "$data_dir/PG_VERSION" ]; then
  data_major=$(cat "$data_dir/PG_VERSION")
  if [ "$data_major" != "$PG_MAJOR" ]; then
    printf 'PostgreSQL %s cannot start with PostgreSQL %s data in %s. Migrate the data or use a fresh Compose project.\n' \
      "$PG_MAJOR" "$data_major" "$data_dir" >&2
    exit 1
  fi
fi

mkdir -p /var/lib/postgresql/data
mkdir -p "${PGBACKREST_REPO_PATH:-/var/lib/pgbackrest}"
mkdir -p /tmp/pgbackrest
mkdir -p /var/log/pgbackrest
mkdir -p /var/spool/pgbackrest
mkdir -p /var/run/postgresql
chown -R postgres:postgres /var/lib/postgresql
chown -R postgres:postgres /var/run/postgresql
chown -R postgres:postgres "${PGBACKREST_REPO_PATH:-/var/lib/pgbackrest}"
chown -R postgres:postgres /tmp/pgbackrest
chown -R postgres:postgres /var/log/pgbackrest
chown -R postgres:postgres /var/spool/pgbackrest

cat >/etc/pgbackrest.conf <<EOF
[global]
lock-path=/tmp/pgbackrest
log-path=/var/log/pgbackrest
repo1-path=${PGBACKREST_REPO_PATH:-/var/lib/pgbackrest}
repo1-retention-full=2
spool-path=/var/spool/pgbackrest
start-fast=y

[${PGBACKREST_STANZA:-patroni-demo}]
pg1-path=${data_dir}
pg1-port=5432
EOF

cat >/tmp/patroni.yml <<EOF
scope: ${CLUSTER_NAME:-pg-ha-demo}
namespace: /service/
name: ${NODE_NAME}

restapi:
  listen: 0.0.0.0:8008
  connect_address: ${RESTAPI_CONNECT_ADDRESS}

etcd3:
  hosts: ${ETCD_ENDPOINTS}
  protocol: http

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    slots:
      postgres1:
        type: physical
      postgres2:
        type: physical
      ${REPLICATION_SLOT_NAME}:
        type: logical
        database: ${APP_DB}
        plugin: pgoutput
    postgresql:
      use_pg_rewind: false
      use_slots: true
      parameters:
        archive_command: 'pgbackrest --stanza=${PGBACKREST_STANZA:-patroni-demo} archive-push %p'
        archive_mode: "on"
        archive_timeout: 60s
        fsync: "off"
        full_page_writes: "off"
        wal_level: logical
        hot_standby: "on"
        max_connections: 200
        max_wal_senders: 10
        max_replication_slots: 10
        synchronous_commit: "off"
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - local all all trust
    - host all all 0.0.0.0/0 scram-sha-256
    - host replication ${REPLICATION_USER} 0.0.0.0/0 scram-sha-256
  post_bootstrap: /scripts/bootstrap.sh

postgresql:
  listen: 0.0.0.0:5432
  connect_address: ${POSTGRES_CONNECT_ADDRESS}
  data_dir: ${data_dir}
  bin_dir: /usr/lib/postgresql/${PG_MAJOR}/bin
  pgpass: /tmp/pgpass
  create_replica_methods:
    - basebackup
  basebackup:
    checkpoint: fast
  authentication:
    superuser:
      username: postgres
      password: ${POSTGRES_SUPERUSER_PASSWORD}
    replication:
      username: ${REPLICATION_USER}
      password: ${REPLICATION_PASSWORD}
  parameters:
    password_encryption: scram-sha-256
    unix_socket_directories: /var/run/postgresql

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF

exec gosu postgres patroni /tmp/patroni.yml
