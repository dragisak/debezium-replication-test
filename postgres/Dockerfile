FROM postgres:19

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl pgbackrest python3 python3-pip \
    && pip3 install --break-system-packages "patroni[etcd3]==4.1.5" "psycopg[binary]==3.3.9" \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
