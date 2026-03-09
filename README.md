# Debezium Replication Test

This repository starts a local stack with:

- Two PostgreSQL nodes managed by Patroni and backed by `etcd`
- One writable leader and one hot standby replica
- HAProxy routing to the current PostgreSQL leader
- PgBouncer as the stable SQL endpoint for clients
- Single-node Kafka in KRaft mode and Kafka Connect with Debezium
- A `test.public.users` table whose changes are published to Kafka as schema-less JSON

Current image/runtime versions:

- PostgreSQL `18.1`
- Patroni `4.1.0`
- etcd `3.6.8`
- HAProxy `3.2-alpine`
- Confluent Kafka `8.2.0` in KRaft mode
- Debezium Connect `3.4.2.Final`

## Services

| Service | Purpose | Host Port |
| --- | --- | --- |
| `postgres1` | Patroni PostgreSQL node | `5433` |
| `postgres2` | Patroni PostgreSQL node | `5434` |
| `haproxy` | Leader-aware PostgreSQL endpoint | `5000` |
| `pgbouncer` | Client SQL endpoint | `6432` |
| `kafka` | Kafka broker | `29092` |
| `connect` | Kafka Connect REST API | `8083` |
| `haproxy` stats | HAProxy dashboard | `8404` |

## Start the stack

```bash
docker compose up -d --build
```

Wait until the connector is registered:

```bash
docker compose logs -f connect-init
```

When setup is complete, you should see `Debezium connector is configured.` in the logs.
The first boot can take around a minute while Patroni initializes the leader and clones the standby.

## Verify PostgreSQL replication

Check Patroni state:

```bash
curl http://localhost:8008/cluster
curl http://localhost:8009/cluster
```

One node should report `Leader` and the other should report `Replica`.

## Write through PgBouncer

Insert or update data through the pooled endpoint:

```bash
docker compose exec pgbouncer \
  psql "postgresql://app_user:app_password@127.0.0.1:6432/test" \
  -c "INSERT INTO public.users (id, name) VALUES (1, 'Alice') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;"
```

Read the replicated table directly from the standby:

```bash
docker compose exec postgres2 \
  psql "postgresql://postgres:postgres@127.0.0.1:5432/test" \
  -c "TABLE public.users;"
```

## Read Kafka events

Debezium writes `public.users` changes to the topic `dbserver1.public.users`.

Consume messages from the broker:

```bash
docker compose exec kafka kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic dbserver1.public.users \
  --from-beginning
```

After inserting or updating rows in `test.public.users`, you should see JSON messages in the consumer output.

## Test failover

Stop the current leader:

```bash
docker compose stop postgres1
```

If `postgres1` was the leader, Patroni should promote `postgres2`. Verify with:

```bash
curl http://localhost:8009/cluster
```

Then write another row through PgBouncer:

```bash
docker compose exec pgbouncer \
  psql "postgresql://app_user:app_password@127.0.0.1:6432/test" \
  -c "INSERT INTO public.users (id, name) VALUES (2, 'Bob') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;"
```

Debezium should continue publishing new change events after the promotion window.

## Notes

- PgBouncer is used for normal SQL traffic only.
- Debezium connects through HAProxy instead of PgBouncer because PostgreSQL logical replication is not compatible with PgBouncer pooling.
- Patroni manages the Debezium logical slot as a permanent slot so it can survive leader promotion.
- PostgreSQL durability is tuned for local development (`fsync=off`, `full_page_writes=off`, `synchronous_commit=off`) so the standby clone and failover loop stay responsive on a laptop.
- To reset everything, run `docker compose down -v`.
