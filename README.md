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

If your repository contains older migrations, set `migrations_path` together with
`migration_command`. The action will automatically run the pre-existing migrations
before analysing the new ones. New files are detected by comparing the pull request's
base and head commits. By default `migration_command` runs **once per migration file**,
appending the file path to the command. Set `once: true` to run the command **a single
 time** with `migrations_path` as its only argument, which is handy for tools that
operate on a directory of migrations.

See https://github.com/agis/pglockanalyze-action/pull/5 for a sample PR demonstrating how one might use this action.

## Status

This software is in *alpha* stage - *expect breakage* and rough edges.

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `input_files` | no | — | Newline-separated list of migration files to analyse, relative to the repo root. Ignored if `migrations_path` is set. |
| `pgla-version` | no | latest | Version of pglockanalyze to use |
| `cli-flags` | no | `--commit` | Extra flags to pass to pglockanalyze |
| `db-host` | no | `localhost` | Host used in the connection string |
| `db-port` | no | `5432` | Port number. |
| `db-name` | no | `pgladb` | Database to create/use for analysis |
| `db-user` | no | `pglauser` | Role created for the run |
| `db-password` | no | `pglapass` | Password for `db-user` |
| `migrations_path` | no | — | Directory or glob pattern pointing to migration files |
| `migration_command` | no | — | YAML object describing how to apply existing migrations. `command` sets the program to run and `once` (default `false`) controls whether the command runs once with `migrations_path` as an argument or once per existing migration file with the file path appended. |

The `cli-flags` input defaults to `--commit` so that each migration is applied inside its own transaction.

At least one of `input_files` or `migrations_path` must be provided. If both are set, `migrations_path` is used only to
apply the existing migrations when `migration_command` is specified.

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
          migrations_path: "migrations/*.sql"
          migration_command: |
            command: ["sql-migrate", "up"]
            once: true
```
