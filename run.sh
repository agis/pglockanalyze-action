#!/usr/bin/env bash
set -euo pipefail

cd "$GITHUB_WORKSPACE"

if [[ -z "${INPUT_FILES:-}" && -z "${MIGRATIONS_PATH:-}" ]]; then
  echo "Either input_files or migrations_path must be provided" >&2
  exit 1
fi

if [[ -n "${MIGRATIONS_PATH:-}" ]]; then
  base_ref=${GITHUB_BASE_REF:-main}
  git fetch --depth=1 origin "$base_ref" >/dev/null 2>&1 || true
  mapfile -t NEW_FILES < <(git diff --name-only --diff-filter=A "origin/$base_ref"...HEAD -- "$MIGRATIONS_PATH" || true)
  mapfile -t ALL_FILES < <(ls -1 "$MIGRATIONS_PATH" 2>/dev/null || true)
  mapfile -t OLD_FILES < <(comm -23 <(printf '%s\n' "${ALL_FILES[@]}" | sort) <(printf '%s\n' "${NEW_FILES[@]}" | sort))

  if [[ -n "${MIGRATION_COMMAND:-}" || -n "${MIGRATION_COMMAND_ONCE:-}" ]]; then
    tmpdir="$(mktemp -d)"
    for f in "${NEW_FILES[@]}"; do
      [ -f "$f" ] || continue
      mkdir -p "$tmpdir/$(dirname "$f")"
      mv "$f" "$tmpdir/$f"
    done

    if [[ -n "${MIGRATION_COMMAND_ONCE:-}" ]]; then
      read -r -a CMD_ARR <<< "$MIGRATION_COMMAND_ONCE"
      "${CMD_ARR[@]}"
    elif [[ -n "${MIGRATION_COMMAND:-}" ]]; then
      read -r -a CMD_ARR <<< "$MIGRATION_COMMAND"
      for f in "${OLD_FILES[@]}"; do
        [ -f "$f" ] || continue
        "${CMD_ARR[@]}" "$f"
      done
    fi

    for f in "${NEW_FILES[@]}"; do
      mkdir -p "$(dirname "$f")"
      mv "$tmpdir/$f" "$f"
    done
  fi

  if [[ -z "${INPUT_FILES:-}" ]]; then
    INPUT_FILES="$(printf '%s\n' "${NEW_FILES[@]}")"
  fi
fi

[[ -z "${INPUT_FILES:-}" ]] && { echo "No migration files to analyse" >&2; exit 1; }

db_conn="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
read -r -a CLI_ARR <<< "${CLI_FLAGS:-}"

while IFS='' read -r relpath; do
  [[ -z "$relpath" ]] && continue
  expanded_path="$GITHUB_WORKSPACE/$relpath"
  [[ ! -f "$expanded_path" ]] && { echo "File not found: $relpath" >&2; continue; }

  result_json="$(pglockanalyze --db "$db_conn" --format=json "${CLI_ARR[@]}" "$expanded_path")"

  echo "$result_json" | jq -c '.[]' | while read -r stmt; do
    start_line=$(echo "$stmt" | jq -r '.location.start_line')
    end_line=$(echo "$stmt" | jq -r '.location.end_line')

    locks=$(echo "$stmt" | jq -r '
      if (.locks_acquired | length) == 0 then
        "No locks acquired"
      else
        [ .locks_acquired[]
          | if .lock_target.relation? then
              "Acquired `" + .mode + "` lock on relation `" + .lock_target.relation.alias + "`"
            else
              "Acquired `" + .mode + "` lock on object `" + .lock_target.object.alias + "`"
            end
        ] | join("%0A")
      end
    ')

    echo "::notice file=${relpath},line=${start_line},endLine=${end_line}::${locks}"
  done
done <<< "$INPUT_FILES"
