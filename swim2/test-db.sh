#!/usr/bin/env bash
# test-db.sh
# Quick smoke-check for the swim-times Postgres database.
# - Ensures the local Postgres container is running (via ../../pg/pg.sh).
# - Creates the swim-times database if missing and applies schema.sql.
# - Lists row counts and a small sample from swim_times.
#
# Usage:
#   ./test-db.sh                # uses ../../pg/pg.sh
#   PG_SH=/path/to/pg.sh ./test-db.sh
#
# Exit status: 0 if schema present and table queryable, non-zero otherwise.

set -euo pipefail
set -x

HERE="$(cd "$(dirname "$0")" && pwd)"
PG_SH="${PG_SH:-$HERE/../../pg/pg.sh}"
SCHEMA="$HERE/schema.sql"
DB_NAME="swim-times"

if [ ! -x "$PG_SH" ]; then
    echo "FAIL: pg.sh wrapper not executable at $PG_SH" >&2
    exit 1
fi
if [ ! -f "$SCHEMA" ]; then
    echo "FAIL: schema.sql not found at $SCHEMA" >&2
    exit 1
fi

echo "=== Ensuring Postgres container is running ==="
"$PG_SH" start

# Wait for the server to accept connections (max ~15 s).
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if "$PG_SH" psql -tAc 'SELECT 1' >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! "$PG_SH" psql -tAc 'SELECT 1' >/dev/null 2>&1; then
    echo "FAIL: Postgres did not accept connections after 15 s" >&2
    exit 1
fi

echo "=== Ensuring database $DB_NAME exists ==="
exists=$("$PG_SH" psql -tAc \
    "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | tr -d '[:space:]')
if [ "$exists" != "1" ]; then
    "$PG_SH" psql -c "CREATE DATABASE \"$DB_NAME\""
fi

echo "=== Applying schema.sql ==="
# Pipe schema in over stdin so we don't need a bind mount.
"$PG_SH" psql -d "$DB_NAME" < "$SCHEMA"

echo "=== Table summary ==="
"$PG_SH" psql -d "$DB_NAME" -c '\dt swim_times'
"$PG_SH" psql -d "$DB_NAME" -c '\d  swim_times'

echo "=== Row count ==="
n=$("$PG_SH" psql -d "$DB_NAME" -tAc 'SELECT count(*) FROM swim_times' \
    | tr -d '[:space:]')
echo "swim_times rows: $n"

echo "=== Sample (top 10 by sort_key) ==="
"$PG_SH" psql -d "$DB_NAME" -c \
    'SELECT swimmer, event, swim_time, swim_date, standard, meet
       FROM swim_times
       ORDER BY sort_key NULLS LAST, swim_date
       LIMIT 10'

echo "PASS: swim_times table is reachable ($n rows)"
