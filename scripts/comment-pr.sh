#!/usr/bin/env bash
set -euo pipefail

JSON_FILE="$1"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "Error: GITHUB_TOKEN is not set. Cannot post PR comments." >&2
  exit 1
fi

export GH_TOKEN="$GITHUB_TOKEN"

# Derive PR number & repo slug from event payload
PR_NUMBER="${PR_NUMBER:-}" # allow override
REPO_SLUG="${GITHUB_REPOSITORY:-}"

if [ -z "$PR_NUMBER" ]; then
  PR_NUMBER=$(jq -r '.pull_request.number' < "$GITHUB_EVENT_PATH")
fi

if [ -z "$PR_NUMBER" ]; then
  echo "Cannot determine PR number" >&2
  exit 1
fi

# Iterate over statements and post inline comments
jq -c '.statements[]' "$JSON_FILE" | while read -r stmt; do
  file=$(echo "$stmt" | jq -r '.location.path // empty')
  start=$(echo "$stmt" | jq -r '.location.start.line // empty')
  body=$(echo "$stmt" | jq -r '.message')

  if [[ -z "$file" || -z "$start" ]]; then
    # fallback to summary comment
    gh pr comment "$PR_NUMBER" --repo "$REPO_SLUG" --body "${body//$'\n'/ }"
  else
    gh pr comment "$PR_NUMBER" \
      --repo "$REPO_SLUG" \
      --body "${body//$'\n'/ }" \
      --path "$file" \
      --line "$start"
  fi

done
