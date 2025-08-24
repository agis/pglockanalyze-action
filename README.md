# pglockanalyze-action

<p align="center">
  <img src="https://github.com/user-attachments/assets/3539ef87-8bce-436c-a826-fbdc4a7da526" />
</p>

Runs [pglockanalyze](https://github.com/agis/pglockanalyze) against a PR with one
or more migration files and reports the results in the diff.

## Usage

You have to bring your own `postgres:` service container (any version), specify the
connection parameters and the action executes pglockanalyze against it using
the files you provide.

If your repository contains older migrations, set `migrations_path` to the
directory containing them together with `migration_command`. The action will automatically run the pre-existing migrations
before analysing the new ones. New files are detected by comparing the pull request's
base and head commits. `migration_command` runs once with `migrations_path` as its
only argument, so it must accept a directory path. The action temporarily moves the
new migrations away, executes the command to apply the existing ones, restores the
new files, and finally analyses them. When no new migrations are found the action
prints a diagnostic message and exits successfully.

See https://github.com/agis/pglockanalyze-action/pull/5 for a sample PR demonstrating how one might use this action.

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

At least one of `input_files` or `migrations_path` must be provided, but not both. When `migrations_path` is used,
`migration_command` must also be provided so the existing migrations can be applied.

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

      - uses: agis/pglockanalyze-action@v1
        with:
          migrations_path: "migrations/"
          migration_command: "sql-migrate up"
```
