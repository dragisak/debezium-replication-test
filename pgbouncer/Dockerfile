FROM postgres:18.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends pgbouncer \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh \
    && mkdir -p /var/run/pgbouncer \
    && chown -R postgres:postgres /var/run/pgbouncer /etc/pgbouncer

USER postgres

ENTRYPOINT ["/entrypoint.sh"]
