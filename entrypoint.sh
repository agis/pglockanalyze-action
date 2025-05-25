#!/usr/bin/env bash
set -euo pipefail

##############################
# 0. Constants & helpers     #
##############################
export PATH="/root/.cargo/bin:$PATH"

log() { echo "[pglockanalyze‑action] $*"; }

##############################
# 1. Start PostgreSQL        #
##############################
log "Booting PostgreSQL $PGVERSION …"
# initialise db cluster if needed
if [ ! -s "/var/lib/postgresql/$PGVERSION/main/PG_VERSION" ]; then
  sudo -u postgres /usr/lib/postgresql/$PGVERSION/bin/initdb -D "/var/lib/postgresql/$PGVERSION/main"
fi
# configure auth for trust on localhost (isolated container)
echo "host all all 0.0.0.0/0 trust" >> "/etc/postgresql/$PGVERSION/main/pg_hba.conf"
# listen on IPv4
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/'" "/etc/postgresql/$PGVERSION/main/postgresql.conf"
# start server
sudo -u postgres /usr/lib/postgresql/$PGVERSION/bin/pg_ctl -D "/var/lib/postgresql/$PGVERSION/main" -o "-p $DB_PORT" -w start

# create user & db (idempotent)
sudo -u postgres psql -v ON_ERROR_STOP=1 <<-SQL
  DO $$
  BEGIN
    IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}'
    ) THEN
      CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
    END IF;
  END$$;
  CREATE DATABASE ${DB_NAME} OWNER ${DB_USER} TEMPLATE template0;
SQL

CONN="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
log "Connection string: ${CONN}"

##############################
# 2. Prepare migration input #
##############################
RESULT_JSON="$(mktemp)"
IFS=$'\n'
readarray -t MIG_LINES <<<"${MIGRATIONS}"

log "Running pglockanalyze …"
# case 1: at least one file path recognised
FILES=()
INLINE=()
for item in "${MIG_LINES[@]}"; do
  if [ -f "$GITHUB_WORKSPACE/$item" ]; then
    FILES+=("$GITHUB_WORKSPACE/$item")
  else
    INLINE+=("$item")
  fi
done

if [ ${#FILES[@]} -gt 0 ]; then
  pglockanalyze --db "$CONN" ${CLI_FLAGS:-} "${FILES[@]}" --format=json >> "$RESULT_JSON"
fi

for ddl in "${INLINE[@]}"; do
  echo "$ddl" | pglockanalyze --db "$CONN" ${CLI_FLAGS:-} --format=json >> "$RESULT_JSON"
done

##############################
# 3. Annotate the PR diff    #
##############################
log "Posting review comments …"
/bash/comment-pr.sh "$RESULT_JSON"
