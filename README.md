# Debezium Replication Test

This repository starts a local stack with:

- Two PostgreSQL nodes managed by Patroni and backed by `etcd`
- One writable leader and one hot standby replica
- HAProxy routing to the current PostgreSQL leader
- PgBouncer as the stable SQL endpoint for clients
- pgBackRest installed on both PostgreSQL nodes with a shared local backup repository
- Single-node Kafka in KRaft mode and Kafka Connect with Debezium
- A `test.public.users` table whose changes are published to Kafka as schema-less JSON

Current image and runtime versions

- PostgreSQL `19`
- Patroni `4.1.5`
- etcd `3.7.4`
- HAProxy `3.2-alpine`
- Confluent Kafka `8.4.1` in KRaft mode
- Debezium Connect `3.7.1.Final`
- pgBackRest from the APT repository configured in `postgres:19`

## Services

| Service | Purpose | Host Port |
| --- | --- | --- |
| `etcd` | Patroni cluster state | `2379` |
| `postgres1` | Patroni PostgreSQL node and REST API | `5433`, `8008` |
| `postgres2` | Patroni PostgreSQL node and REST API | `5434`, `8009` |
| `haproxy` | Leader-aware PostgreSQL endpoint | `5000` (override with `HAPROXY_HOST_PORT`) |
| `pgbouncer` | Client SQL endpoint | `6432` |
| `kafka` | Kafka broker | `29092` |
| `connect` | Kafka Connect REST API | `8083` |
| `haproxy` stats | HAProxy dashboard | `8404` |

## Start the stack

If you have PostgreSQL 18 volumes, stop that stack before starting PostgreSQL 19 on the same ports. To start a fresh cluster and keep the old volumes, select a new Compose project in the shell where you run the commands below. To carry over the old data, follow the [PostgreSQL major-version upgrade guide](https://www.postgresql.org/docs/19/upgrading.html).

```bash
export COMPOSE_PROJECT_NAME=debezium-replication-pg19
```

If host port `5000` is already in use, for example by AirPlay Receiver on macOS, run `export HAPROXY_HOST_PORT=15000` in that shell.

```bash
docker compose up -d --build
```

Wait until the connector is registered:

```bash
docker compose logs -f connect-init
```

When the connector is registered, you should see `Debezium connector is configured.` in the logs.
The first boot can take around a minute while Patroni initializes the leader and clones the standby.

Check that the connector and its task both report `RUNNING`.

```bash
curl -fsS http://localhost:8083/connectors/users-connector/status
```

## Initialize pgBackRest on the current primary

Check which Patroni node is the leader:

```bash
curl http://localhost:8008/cluster
curl http://localhost:8009/cluster
```

Run `stanza-create` and `check` as `postgres` on the leader container. Replace `postgres1` with `postgres2` if the second node is primary. Initial WAL archiving waits for the stanza to exist.

```bash
docker compose exec -u postgres postgres1 \
  pgbackrest --stanza=patroni-demo --log-level-console=info stanza-create

docker compose exec -u postgres postgres1 \
  pgbackrest --stanza=patroni-demo --log-level-console=info check
```

Create a full backup of the primary database:

```bash
docker compose exec -u postgres postgres1 \
  pgbackrest --stanza=patroni-demo --type=full --log-level-console=info backup
```

List the backups stored in the shared repository volume:

```bash
docker compose exec -u postgres postgres1 \
  pgbackrest --stanza=patroni-demo --output=json info
```

## Verify PostgreSQL replication

Check Patroni state:

```bash
curl http://localhost:8008/cluster
curl http://localhost:8009/cluster
```

Each endpoint should show one `leader` and one `replica` in the `members` list. A ready replica reports `state: streaming`.

## Write through PgBouncer

Insert or update data through the pooled endpoint:

```bash
docker compose exec pgbouncer \
  psql "postgresql://app_user:app_password@127.0.0.1:6432/test" \
  -c "INSERT INTO public.users (id, name) VALUES (1, 'Alice') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;"
```

Read the replicated table directly from the standby. Replace `postgres2` with `postgres1` if the first node is the replica.

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

Stop the current leader. This example assumes `postgres1` is the leader.

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

Start the former leader again and check that it rejoins as a streaming replica.

```bash
docker compose start postgres1
curl http://localhost:8009/cluster
```

## Notes

- PgBouncer is used for normal SQL traffic only.
- Debezium connects through HAProxy instead of PgBouncer because PostgreSQL logical replication is not compatible with PgBouncer pooling.
- Patroni manages the Debezium logical slot as a permanent slot so it can survive leader promotion.
- pgBackRest is configured via `/etc/pgbackrest.conf` inside each PostgreSQL container and stores backups in the shared Docker volume mounted at `/var/lib/pgbackrest`.
- PostgreSQL durability is tuned for local development (`fsync=off`, `full_page_writes=off`, `synchronous_commit=off`) so the standby clone and failover loop stay responsive on a laptop.
- To reset everything, run `docker compose down -v`.
