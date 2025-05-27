#!/usr/bin/env bash
set -euo pipefail

CONN="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

[[ -z "${FILE_INPUTS:-}" ]] && { echo "input_files is required and empty" >&2; exit 1; }

while IFS='' read -r relpath; do
  [[ -z "$relpath" ]] && continue
  full="$GITHUB_WORKSPACE/$relpath"

  if [[ ! -f "$full" ]]; then
    echo "File not found: $relpath" >&2
    continue
  fi

  echo "Analyzing $relpath"
  result_json="$(pglockanalyze --db "$CONN" ${CLI_FLAGS:-} "$full" --format=json)"

  echo "$result_json" | jq -c '.[]' | while read -r stmt; do
    start_line=$(echo "$stmt" | jq -r '.location.start_line')
    end_line=$(echo "$stmt" | jq -r '.location.end_line')
    sql=$(echo "$stmt" | jq -r '.sql')
    locks=$(echo "$stmt" | jq -r '[.locks_acquired[] | .mode + " on " + (.lock_target.relation.alias // "?")] | join(", ")')
    echo "::notice title=Locks acquired,file=${relpath},line=${start_line},endLine=${end_line}::${sql}\nLocks: ${locks}"
  done

done <<<"$FILE_INPUTS"
