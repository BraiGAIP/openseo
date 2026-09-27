#!/usr/bin/env bash
# Apply the OpenSEO migrations to a throw-away PostgreSQL cluster and run the
# RLS / business-rule tests. Requires PostgreSQL 15+ binaries on PATH or in
# /usr/lib/postgresql/<ver>/bin.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PGBIN="${PGBIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
export PATH="$PGBIN:$PATH"

TMP="$(mktemp -d)"
PORT="${PGPORT_TEST:-54329}"
cleanup() { pg_ctl -D "$TMP/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

RUN_AS=()
if [ "$(id -u)" = "0" ]; then
  # initdb refuses to run as root → use the postgres system user if present.
  chown -R postgres "$TMP"
  RUN_AS=(runuser -u postgres --)
fi

"${RUN_AS[@]}" initdb -D "$TMP/data" -U postgres -A trust >/dev/null
"${RUN_AS[@]}" pg_ctl -D "$TMP/data" -o "-p $PORT -k $TMP -c listen_addresses=''" -l "$TMP/log" -w start >/dev/null

PSQL=(psql -h "$TMP" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -X -q)
"${PSQL[@]}" -c "create database openseo_test"
"${PSQL[@]}" -d openseo_test -c "alter database openseo_test set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d openseo_test -f "$HERE/supabase_stub.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "applying $(basename "$f")"
  "${PSQL[@]}" -d openseo_test --single-transaction -f "$f"
done
if [ "${FINGERPRINT:-0}" = "1" ]; then "${PSQL[@]}" -d openseo_test -f "$HERE/fingerprint.sql"; exit 0; fi
"${PSQL[@]}" -d openseo_test -f "$HERE/rls_isolation_test.sql"
