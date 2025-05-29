#!/usr/bin/env bash
set -euo pipefail

CONN="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

[[ -z "${FILE_INPUTS:-}" ]] && { echo "input_files is required and empty" >&2; exit 1; }

while IFS='' read -r relpath; do
  [[ -z "$relpath" ]] && continue
  full="$GITHUB_WORKSPACE/$relpath"
  [[ ! -f "$full" ]] && { echo "File not found: $relpath" >&2; continue; }

  result_json="$(pglockanalyze --db "$CONN" ${CLI_FLAGS:-} "$full" --format=json)"

  echo "$result_json" | jq -c '.[]' | while read -r stmt; do
    start_line=$(echo "$stmt" | jq -r '.location.start_line')
    end_line=$(echo   "$stmt" | jq -r '.location.end_line')

    locks=$(
      echo "$stmt" |
        jq -r '[.locks_acquired[] |
                  (if .lock_target.relation?
                     then "Acquired " + .mode + " on relation `" + .lock_target.relation.alias + "`"
                     else "Acquired " + .mode + " on object `"  + .lock_target.object.alias   + "`"
                   end)
                 + " ([docs](https://www.postgresql.org/docs/current/explicit-locking.html))"
               ] | join("%0A")'
    )

    echo "::notice title=Locks acquired,file=${relpath},line=${start_line},endLine=${end_line}::${locks}"
  done

done <<<"$FILE_INPUTS"
