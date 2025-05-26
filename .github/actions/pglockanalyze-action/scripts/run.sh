#!/usr/bin/env bash
set -exuo pipefail

log() { echo "[pglockanalyze-action] $*"; }

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-pgladb}"
DB_USER="${DB_USER:-pglauser}"
DB_PASS="${DB_PASS:-pglapass}"

CONN="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
log "Using connection: $CONN"

RESULT_JSON="$(mktemp)"

########################################
# 1. Collect file inputs
########################################
FILES=()
if [[ -n "${FILE_INPUTS:-}" ]]; then
  while IFS='' read -r line; do
    [[ -z "$line" ]] && continue
    full="$GITHUB_WORKSPACE/$line"
    if [[ -f "$full" ]]; then
      FILES+=("$full")
    else
      log "⚠️  File not found: $line"
    fi
  done <<<"$FILE_INPUTS"
fi

########################################
# 2. Collect inline DDL statements
########################################
INLINE=()
if [[ -n "${INLINE_DDL:-}" ]]; then
  while IFS='' read -r stmt; do
    [[ -z "$stmt" ]] && continue
    INLINE+=("$stmt")
  done <<<"$INLINE_DDL"
fi

[[ ${#FILES[@]} -eq 0 && ${#INLINE[@]} -eq 0 ]] && {
  echo "❌ No migrations provided via 'input_files' or 'input_inline'." >&2
  exit 1
}

########################################
# 3. Run pglockanalyze (one file / stmt at a time)
########################################
log "Running pglockanalyze …"

# ── 3a. File-based migrations ────────────────────────────
for file in "${FILES[@]}"; do
  pglockanalyze --db "$CONN" ${CLI_FLAGS:-} "$file" --format=json >>"$RESULT_JSON"
done

# ── 3b. Inline statements ────────────────────────────────
for ddl in "${INLINE[@]}"; do
  echo "$ddl" | pglockanalyze --db "$CONN" ${CLI_FLAGS:-} --format=json >>"$RESULT_JSON"
done

########################################
# 4. Post review comments
########################################
log "Analysis complete; output at $RESULT_JSON"
"${GITHUB_ACTION_PATH:-${0%/*}}/comment-pr.sh" "$RESULT_JSON"
