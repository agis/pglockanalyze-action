# pglockanalyze-action

<p align="center">
  <img src="https://github.com/user-attachments/assets/3539ef87-8bce-436c-a826-fbdc4a7da526" />
</p>

Runs [pglockanalyze](https://github.com/agis/pglockanalyze) against a PR with one
or more migration files and reports the results in the diff.

## Usage

You have to bring your own `postgres:` service container, specify the
connection parameters and the action executes pglockanalyze against it using
the migrations you provide.

See https://github.com/agis/pglockanalyze-action/pull/5 for a sample PR demonstrating how one might use this action.

### Provisioning database

Most commonly you'll need to bring your database to proper state before
analyzing the migrations. For example you might need to execute pre-existing
migrations (i.e. those existing before the PR being analyzed). For this reason
set `migrations_path` to the directory containing the migrations, together with
`migration_command`. The action will then apply the pre-existing migrations
before analysing the new ones. New files are detected by comparing the pull
request's base and head commits.

If you want to do the provisioning yourself, just set `input_files` instead.


## Status

This software is in *alpha* stage - *expect breakage* and rough edges.

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `input_files` | no | — | Newline-separated list of migration files to analyse, relative to the repo root. Cannot be used together with `migrations_path`. |
| `pgla-version` | no | latest | Version of pglockanalyze to use |
| `cli-flags` | no | `--commit` | Extra flags to pass to pglockanalyze |
| `db-host` | no | `localhost` | Host used in the connection string |
| `db-port` | no | `5432` | Port number. |
| `db-name` | no | `pgladb` | Database to create/use for analysis |
| `db-user` | no | `pglauser` | Role created for the run |
| `db-password` | no | `pglapass` | Password for `db-user` |
| `migrations_path` | no | — | Directory containing migration files. Must exist. Requires `migration_command` and cannot be combined with `input_files`. |
| `migration_command` | no | — | Command used to apply existing migrations. Runs once with `migrations_path` as its only argument. |

The `cli-flags` input defaults to `--commit` so that each migration is applied inside its own transaction.

At least one of `input_files` or `migrations_path` must be provided, but not
both. When `migrations_path` is used,
`migration_command` must also be provided so the existing migrations can be
applied.

---

## Minimal example

```yaml
name: lock-check
on:
  pull_request:

jobs:
  analyze:
    runs-on: ubuntu-latest

    services:
      db:
        image: postgres:16
        env:
          POSTGRES_USER: pglauser
          POSTGRES_PASSWORD: pglapass
          POSTGRES_DB: pgladb
        ports: [5432:5432]

    steps:
      - uses: actions/checkout@v4
        # necessary if `migrations_path` is set
        fetch-depth: 0

      - uses: agis/pglockanalyze-action@v0.0.11
        with:
          migrations_path: "migrations/*.sql"
          migration_command: "sql-migrate up"
```
