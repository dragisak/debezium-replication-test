# AGENTS.md

## Repo overview
- This repository provides a local Debezium replication test stack built with `docker compose`.
- The stack includes Patroni-managed PostgreSQL nodes, `etcd`, HAProxy, PgBouncer, Kafka, and Kafka Connect.
- The main workflow is: start the stack, wait for connector registration, write to `public.users`, and verify Debezium events.

## Important files
- `docker-compose.yml`: source of truth for service wiring, ports, health checks, and startup order.
- `README.md`: expected user workflow, verification steps, and reset instructions.
- `postgres/`: PostgreSQL image and bootstrap logic.
- `haproxy/`: leader-aware routing configuration for PostgreSQL clients.
- `pgbouncer/`: pooled SQL endpoint config and container entrypoint.
- `debezium/`: Kafka Connect connector payloads and registration config.

## Working rules
- Prefer minimal changes that preserve the local-development purpose of this repo.
- Keep service names, exposed ports, and documented commands aligned with `README.md`.
- When changing container behavior, update both `docker-compose.yml` and any impacted service config together.
- Do not add production-oriented hardening unless explicitly requested; this repo is intentionally tuned for local testing.
- Preserve the distinction that PgBouncer handles normal SQL traffic while Debezium connects through HAProxy.

## Validation
- For config-only changes, sanity-check consistency across `docker-compose.yml`, service configs, and `README.md`.
- For behavior changes, prefer validating with `docker compose config` first.
- If the user asks for runtime verification, use the commands documented in `README.md`.

## Editing guidance
- Keep JSON files compact and valid.
- Keep shell scripts POSIX-compatible unless the existing file clearly relies on Bash-specific behavior.
- Avoid renaming services or directories unless the user explicitly asks for it.
