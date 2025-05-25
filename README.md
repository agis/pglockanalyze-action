# 🚦 pglockanalyze‑action (composite)

Composite GitHub Action that analyses PostgreSQL migrations for lock impact
using the **pglockanalyze** CLI, then posts inline PR comments.

---

## How it works

1. **You** declare a PostgreSQL **service container** in the job  
   (any tag from `postgres:`—that’s where the version is chosen).
2. The action installs `pglockanalyze` on the runner.
3. Each migration file / inline DDL is executed inside a transaction; the
   locks are captured and reported.
4. Comments are posted on the pull‑request diff via the GitHub CLI.

---

## Example workflow

```yaml
name: lock-check
on:
  pull_request:
    paths:
      - "migrations/**/*.sql"

jobs:
  analyze:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write

    services:
      db:
        image: postgres:16
        env:
          POSTGRES_USER: pglauser
          POSTGRES_PASSWORD: pglapass
          POSTGRES_DB: pgladb
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4

      - name: pglockanalyze
        uses: YOURORG/pglockanalyze-action@v2
        with:
          migrations: |
            migrations/20240525_add_index.sql
            ALTER TABLE users ADD COLUMN last_seen timestamptz;
```

Pick any Postgres image tag—`postgres:14`, `14-alpine`, `15`, `16`—the action
adapts via its connection inputs.

---

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `db-host` | `localhost` | Host of the Postgres service |
| `db-port` | `5432` | Port exposed by the service |
| `db-name` | `pgladb` | Database name |
| `db-user` | `pglauser` | Role used for analysis |
| `db-password` | `pglapass` | Password for `db-user` |
| `migrations` | *(required)* | List of file paths or raw DDL (newline‑separated) |
| `cli-flags` | *(empty)* | Extra flags forwarded to `pglockanalyze` |
| `github-token` | `${{ github.token }}` | Token used to post review comments |

---

## Local testing with **act**

```bash
export PGLA_ACTION_TOKEN=dummy   # set to PAT if you want gh comments

act pull_request \
  -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:full-22.04 \
  -s GITHUB_TOKEN=$PGLA_ACTION_TOKEN
```

The full runner image already contains Docker so the `postgres:` service
container spins up automatically.
