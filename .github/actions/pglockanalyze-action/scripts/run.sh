#!/usr/bin/env bash
set -euo pipefail

log() { echo "[pglockanalyze-action] $*"; }

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-pgladb}"
DB_USER="${DB_USER:-pglauser}"
DB_PASS="${DB_PASS:-pglapass}"

CONN="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
log "Using connection: $CONN"

RESULT_JSON="$(mktemp)"
IFS=$'\n'
readarray -t MIG_LINES <<<"${MIGRATIONS}"

FILES=()
INLINE=()
for item in "${MIG_LINES[@]}"; do
  if [[ -f "$GITHUB_WORKSPACE/$item" ]]; then
    FILES+=("$GITHUB_WORKSPACE/$item")
  elif [[ -n "$item" ]]; then
    INLINE+=("$item")
  fi
done

if [[ ${#FILES[@]} -gt 0 ]]; then
  pglockanalyze --db "$CONN" ${CLI_FLAGS:-} "${FILES[@]}" --format=json >> "$RESULT_JSON"
fi

for ddl in "${INLINE[@]}"; do
  echo "$ddl" | pglockanalyze --db "$CONN" ${CLI_FLAGS:-} --format=json >> "$RESULT_JSON"
done

log "Analysis complete; output at $RESULT_JSON"
"${GITHUB_ACTION_PATH:-${0%/*}}/scripts/comment-pr.sh" "$RESULT_JSON"
