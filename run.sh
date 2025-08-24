#!/usr/bin/env bash
# Exit immediately on errors, treat unset variables as errors, and fail when any command in a pipeline fails
set -euo pipefail

# Work from the repository root
cd "$GITHUB_WORKSPACE"

# Ensure we are running in a pull request context
if [[ -z "${BASE_SHA:-}" || -z "${HEAD_SHA:-}" ]]; then
  echo "No base or head reference detected. Are we not executing in a PR?" >&2
  exit 1
fi

# Ensure the user doesn't mix incompatible inputs
if [[ -n "${INPUT_FILES:-}" && -n "${MIGRATIONS_PATH:-}" ]]; then
  echo "input_files and migrations_path cannot be used together" >&2
  exit 1
fi

# When migrations_path is provided we require a command to apply them
if [[ -n "${MIGRATIONS_PATH:-}" && -z "${MIGRATION_COMMAND:-}" ]]; then
  echo "migration_command is required when migrations_path is set" >&2
  exit 1
fi

# The action needs either explicit files or a path to search for migrations
if [[ -z "${INPUT_FILES:-}" && -z "${MIGRATIONS_PATH:-}" ]]; then
  echo "Either input_files or migrations_path must be provided" >&2
  exit 1
fi

if [[ -n "${MIGRATIONS_PATH:-}" ]]; then
  # Determine which migrations are new in this pull request
  base_sha="$BASE_SHA"
  head_sha="$HEAD_SHA"
  mapfile -t NEW_MIGRATIONS < <(git diff --name-only --diff-filter=A "$base_sha...$head_sha" -- "$MIGRATIONS_PATH" || true)

  # Exit early when no new migrations were added
  if [[ ${#NEW_MIGRATIONS[@]} -eq 0 ]]; then
    echo "No new migrations found under '$MIGRATIONS_PATH'. Nothing to analyse."
    exit 0
  fi

  # Temporarily move new migrations away so they are not applied
  tmpdir="$(mktemp -d)"
  for f in "${NEW_MIGRATIONS[@]}"; do
    [ -f "$f" ] || continue
    mv "$f" "$tmpdir/$(basename "$f")"
  done

  # Resolve the directory to pass to the migration command
  migration_dir="$MIGRATIONS_PATH"
  if [[ ! -d "$migration_dir" ]]; then
    migration_dir="$(dirname "$MIGRATIONS_PATH")"
  fi
  if [[ ! -d "$migration_dir" ]]; then
    echo "migrations_path must resolve to an existing directory" >&2
    exit 1
  fi

  # Run the user-supplied command once, passing the directory
  read -r -a CMD_ARR <<< "$MIGRATION_COMMAND"
  "${CMD_ARR[@]}" "$migration_dir"

  # Restore the new migrations to their original locations
  for f in "${NEW_MIGRATIONS[@]}"; do
    mv "$tmpdir/$(basename "$f")" "$f"
  done

  # Analyse the new migrations
  INPUT_FILES="$(printf '%s\n' "${NEW_MIGRATIONS[@]}")"
fi

# Abort if we still have nothing to analyse
[[ -z "${INPUT_FILES:-}" ]] && { echo "No migration files to analyse" >&2; exit 1; }

# Build the database connection string for pglockanalyze
db_conn="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

# Split any extra CLI flags into an array
read -r -a CLI_ARR <<< "${CLI_FLAGS:-}"

# Process each migration file
while IFS='' read -r relpath; do
  [[ -z "$relpath" ]] && continue
  expanded_path="$GITHUB_WORKSPACE/$relpath"
  [[ ! -f "$expanded_path" ]] && { echo "File not found: $relpath" >&2; continue; }

  # Run pglockanalyze and capture JSON output
  result_json="$(pglockanalyze --db "$db_conn" --format=json "${CLI_ARR[@]}" "$expanded_path")"

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
