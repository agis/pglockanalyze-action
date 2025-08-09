#!/usr/bin/env bash
set -euo pipefail

db_conn="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

# Function to run pglockanalyze on a list of files
run_pglockanalyze() {
  local files="$1"
  
  while IFS='' read -r relpath; do
    [[ -z "$relpath" ]] && continue
    expanded_path="$GITHUB_WORKSPACE/$relpath"
    [[ ! -f "$expanded_path" ]] && { echo "File not found: $relpath" >&2; continue; }

    result_json="$(pglockanalyze --db "$db_conn" --format=json ${CLI_FLAGS:-} "$expanded_path")"

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
  done <<< "$files"
}

# Auto-detection mode when migration-path is provided
if [[ -n "${MIGRATION_PATH:-}" ]]; then
  [[ -z "${MIGRATION_CMD:-}" ]] && { echo "migration-command is required when migration-path is provided" >&2; exit 1; }
  
  echo "Auto-detecting new migration files..."
  
  # Get the base branch for PR comparison
  # In GitHub Actions, GITHUB_BASE_REF contains the target branch for PRs
  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    base_branch="origin/$GITHUB_BASE_REF"
  else
    # Fallback for direct pushes or when not in PR context
    base_branch=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||' || echo "main")
    if ! git rev-parse --verify "origin/$base_branch" >/dev/null 2>&1; then
      base_branch="master"
      if ! git rev-parse --verify "origin/$base_branch" >/dev/null 2>&1; then
        echo "Could not determine base branch. Using HEAD~1" >&2
        base_branch="HEAD~1"
      else
        base_branch="origin/$base_branch"
      fi
    else
      base_branch="origin/$base_branch"
    fi
  fi
  
  echo "Using base branch: $base_branch"
  
  # Find all migration files in the specified path
  all_migrations=()
  while IFS= read -r -d '' file; do
    all_migrations+=("$file")
  done < <(find "$GITHUB_WORKSPACE/$MIGRATION_PATH" -name "*.sql" -type f -print0 2>/dev/null || true)
  
  if [[ ${#all_migrations[@]} -eq 0 ]]; then
    echo "No migration files found in path: $MIGRATION_PATH" >&2
    exit 1
  fi
  
  # Detect new/changed migration files
  new_migrations=()
  echo "Comparing against base branch: $base_branch"
  
  for migration in "${all_migrations[@]}"; do
    relpath=$(realpath --relative-to="$GITHUB_WORKSPACE" "$migration")
    # Check if file is new or modified in current branch
    if git diff --name-only "$base_branch"...HEAD -- "$relpath" | grep -q .; then
      new_migrations+=("$relpath")
    fi
  done
  
  if [[ ${#new_migrations[@]} -eq 0 ]]; then
    echo "No new migration files detected in current branch"
    exit 0
  fi
  
  echo "Detected ${#new_migrations[@]} new migration file(s):"
  printf '  %s\n' "${new_migrations[@]}"
  
  # Create temporary directory for new migrations
  temp_dir=$(mktemp -d)
  trap "rm -rf '$temp_dir'" EXIT
  
  # Move new migration files to temp directory
  for migration in "${new_migrations[@]}"; do
    full_path="$GITHUB_WORKSPACE/$migration"
    if [[ -f "$full_path" ]]; then
      cp "$full_path" "$temp_dir/"
      rm "$full_path"
    fi
  done
  
  # Run migration command on existing migrations
  echo "Running migration command on existing migrations..."
  cd "$GITHUB_WORKSPACE"
  if ! eval "$MIGRATION_CMD"; then
    # Restore new migration files before exiting
    for migration in "${new_migrations[@]}"; do
      full_path="$GITHUB_WORKSPACE/$migration"
      filename=$(basename "$migration")
      if [[ -f "$temp_dir/$filename" ]]; then
        cp "$temp_dir/$filename" "$full_path"
      fi
    done
    echo "Migration command failed" >&2
    exit 1
  fi
  
  # Restore new migration files
  for migration in "${new_migrations[@]}"; do
    full_path="$GITHUB_WORKSPACE/$migration"
    filename=$(basename "$migration")
    if [[ -f "$temp_dir/$filename" ]]; then
      cp "$temp_dir/$filename" "$full_path"
    fi
  done
  
  # Run pglockanalyze on new migrations
  echo "Running pglockanalyze on new migration files..."
  new_files_list=$(printf '%s\n' "${new_migrations[@]}")
  run_pglockanalyze "$new_files_list"

# Traditional mode with explicit input_files
else
  [[ -z "${INPUT_FILES:-}" ]] && { echo "Either input_files or migration-path must be provided" >&2; exit 1; }
  run_pglockanalyze "$INPUT_FILES"
fi
