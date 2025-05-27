#!/usr/bin/env bash
set -euo pipefail

JSON_FILE="$1"

# Iterate over every statement in the combined pglockanalyze output
jq -c '.statements[]' "$JSON_FILE" | while read -r stmt; do
  file=$(echo "$stmt" | jq -r '.location.path // empty')
  line=$(echo "$stmt" | jq -r '.location.start.line // empty')
  body=$(echo "$stmt" | jq -r '.message')

  # Fallback: no file/line info → plain notice
  if [[ -z "$file" || -z "$line" ]]; then
    echo "::notice ::$body"
  else
    # Emit an annotation tied to a specific line in the PR diff
    echo "::notice file=${file},line=${line}::$body"
  fi
done
