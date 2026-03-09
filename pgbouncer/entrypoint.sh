#!/usr/bin/env bash
set -euo pipefail

exec pgbouncer /etc/pgbouncer/pgbouncer.ini
