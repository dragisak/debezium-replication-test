#!/usr/bin/env bash
set -euo pipefail

conn_string="${1:-postgresql://postgres:${POSTGRES_SUPERUSER_PASSWORD}@127.0.0.1:5432/postgres}"

psql "${conn_string}" -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${REPLICATION_USER}') THEN
    EXECUTE format('CREATE ROLE %I LOGIN REPLICATION PASSWORD %L', '${REPLICATION_USER}', '${REPLICATION_PASSWORD}');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${APP_USER}') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${APP_USER}', '${APP_PASSWORD}');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${DEBEZIUM_USER}') THEN
    EXECUTE format('CREATE ROLE %I LOGIN REPLICATION PASSWORD %L', '${DEBEZIUM_USER}', '${DEBEZIUM_PASSWORD}');
  END IF;
END
\$\$;

SELECT format('CREATE DATABASE %I OWNER %I', '${APP_DB}', '${APP_USER}')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${APP_DB}')\gexec

\connect ${APP_DB}

CREATE TABLE IF NOT EXISTS public.users (
  id integer PRIMARY KEY,
  name text NOT NULL
);

ALTER TABLE public.users OWNER TO ${APP_USER};
GRANT CONNECT ON DATABASE ${APP_DB} TO ${DEBEZIUM_USER};
GRANT USAGE ON SCHEMA public TO ${DEBEZIUM_USER};
GRANT SELECT ON TABLE public.users TO ${DEBEZIUM_USER};
ALTER DEFAULT PRIVILEGES FOR ROLE ${APP_USER} IN SCHEMA public GRANT SELECT ON TABLES TO ${DEBEZIUM_USER};

DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = '${PUBLICATION_NAME}') THEN
    EXECUTE format('CREATE PUBLICATION %I FOR TABLE public.users', '${PUBLICATION_NAME}');
  END IF;
END
\$\$;

SELECT format(
  'SELECT pg_create_logical_replication_slot(%L, ''pgoutput'', false, false, true);',
  '${REPLICATION_SLOT_NAME}'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = '${REPLICATION_SLOT_NAME}')\gexec
SQL
