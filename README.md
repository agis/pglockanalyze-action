# 🚦 pglockanalyze‑action

A reusable **GitHub Action** that checks your PostgreSQL migrations for blocking locks *before* they reach production.  Powered by the [pglockanalyze](https://github.com/…) CLI.

---
## ✨ Features
* Spins up the exact PostgreSQL version you specify.
* Installs `pglockanalyze` from crates.io on every run to ensure the latest release.
* Accepts **migration files** *or* **inline DDL**.
* Posts **inline** pull‑request comments showing the lock each statement would acquire.

---
## 📦 Inputs
| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `postgres-version` | ❌ | `16` | PostgreSQL major version to install & start |
| `db-name` | ❌ | `pgladb` | Name of the database to create |
| `db-user` | ❌ | `pglauser` | Database user |
| `db-password` | ❌ | `pglapass` | Password for `db-user` |
| `db-host` | ❌ | `localhost` | Host for connection string (inside container) |
| `db-port` | ❌ | `5432` | Port for Postgres |
| `migrations` | ✅ |  | New‑line separated list of **paths** or **DDL statements** |
| `cli-flags` | ❌ |  | Additional flags forwarded to `pglockanalyze` |
| `github-token` | ❌ | `${{ github.token }}` | Token used to post review comments |

---
## 🚀 Usage
Add a job to your workflow:

```yaml
name: lock‑check
on:
  pull_request:
    paths:
      - "migrations/**.sql"

jobs:
  analyze:
    runs-on: ubuntu-latest
    permissions: { pull-requests: write }
    steps:
      - uses: actions/checkout@v4

      - name: pglockanalyze migrations
        uses: YOURORG/pglockanalyze-action@v1
        with:
          postgres-version: 16
          migrations: |
            migrations/20240525_add_index.sql
            ALTER TABLE users ALTER COLUMN email SET NOT NULL;
```

The action will post comments directly on the modified lines **only if** the `location` data returned by the CLI includes a file path & line numbers; otherwise it falls back to a top‑level PR comment.

---
## 🛠 Development & Testing
Clone this repo and run the [dev workflow](.github/workflows/test.yml) locally using [act](https://github.com/nektos/act):

```bash
act pull_request -W .github/workflows/test.yml -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:full-22.04
```

---
## 📄 License
MIT
