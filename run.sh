#!/usr/bin/env bash
set -euo pipefail

CONN="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

[[ -z "${INPUT_FILES:-}" ]] && { echo "input_files is empty" >&2; exit 1; }

while IFS='' read -r relpath; do
  [[ -z "$relpath" ]] && continue
  expanded_path="$GITHUB_WORKSPACE/$relpath"
  [[ ! -f "$expanded_path" ]] && { echo "File not found: $relpath" >&2; continue; }

  result_json="$(pglockanalyze --db "$CONN" ${CLI_FLAGS:-} "$expanded_path" --format=json)"

  echo "$result_json" | jq -c '.[]' | while read -r stmt; do
    start_line=$(echo "$stmt" | jq -r '.location.start_line')
    end_line=$(echo "$stmt" | jq -r '.location.end_line')

    locks=$(echo "$stmt" | jq -r '
      if (.locks_acquired | length) == 0 then
        "No locks acquired"
      else
        [ .locks_acquired[]
          | if .lock_target.relation? then
              "Acquired " + .mode + " on relation `" + .lock_target.relation.alias + "`"
            else
              "Acquired " + .mode + " on object `" + .lock_target.object.alias + "`"
            end
        ] | join("%0A")
      end
    ')

    echo "::notice file=${relpath},line=${start_line},endLine=${end_line}::${locks}"
  done
done <<< "$FILE_INPUTS"
