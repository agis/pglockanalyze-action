#!/usr/bin/env bash
set -euo pipefail

cd "$GITHUB_WORKSPACE"

if [[ -n "${INPUT_FILES:-}" && -n "${MIGRATIONS_PATH:-}" ]]; then
  echo "input_files and migrations_path cannot be used together" >&2
  exit 1
fi

if [[ -z "${INPUT_FILES:-}" && -z "${MIGRATIONS_PATH:-}" ]]; then
  echo "Either input_files or migrations_path must be provided" >&2
  exit 1
fi

if [[ -n "${MIGRATIONS_PATH:-}" ]]; then
  # inputs validations
  if [[ -z "${BASE_SHA:-}" || -z "${HEAD_SHA:-}" ]]; then
    echo "No git base or head reference found to compute changed migrations from. Are we not executing in a PR?" >&2
    exit 1
  fi

  if [[ -z "${MIGRATION_COMMAND:-}" ]]; then
    echo "migration_command is required when migrations_path is set" >&2
    exit 1
  fi

  if [[ -n "${MIGRATION_COMMAND:-}" && ! -x "$(command -v "${MIGRATION_COMMAND%% *}")" ]]; then
    echo "migration_command '${MIGRATION_COMMAND%% *}' not found" >&2
    exit 1
  fi

  # Compute migrations added in the current PR
  mapfile -t NEW_MIGRATIONS < <(git diff --name-only --diff-filter=A "$BASE_SHA...$HEAD_SHA" -- "$MIGRATIONS_PATH" || true)
  if [[ ${#NEW_MIGRATIONS[@]} -eq 0 ]]; then
    echo "No new migrations found under '$MIGRATIONS_PATH'. Nothing to analyse."
    exit 0
  fi

  # Temporarily move new migrations away so they are not applied when we execute
  # migration_command
  tmpdir="$(mktemp -d)"
  for f in "${NEW_MIGRATIONS[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "New migration '$f' is not a file" >&2
      exit 1
    fi
    mv "$f" "$tmpdir/$(basename "$f")"
  done

  read -r -a CMD_ARR <<< "$MIGRATION_COMMAND"
  "${CMD_ARR[@]}"

  # Move new migrations back to their original location, so that we don't leave
  # a dirty git tree behind
  for f in "${NEW_MIGRATIONS[@]}"; do
    mv "$tmpdir/$(basename "$f")" "$f"
  done

  INPUT_FILES="$(printf '%s\n' "${NEW_MIGRATIONS[@]}")"
fi

[[ -z "${INPUT_FILES:-}" ]] && { echo "No migration files to analyse" >&2; exit 1; }

db_conn="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

# Split any extra CLI flags into an array
read -r -a PGLA_FLAGS <<< "${CLI_FLAGS:-}"

# analyze migrations
while IFS='' read -r relpath; do
  [[ -z "$relpath" ]] && continue
  expanded_path="$GITHUB_WORKSPACE/$relpath"
  [[ ! -f "$expanded_path" ]] && { echo "File not found: $relpath" >&2; continue; }

  result_json="$(pglockanalyze --db "$db_conn" --format=json "${PGLA_FLAGS[@]}" "$expanded_path")"

  # Emit a notice for every statement in the report
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
