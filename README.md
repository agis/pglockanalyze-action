# pglockanalyze-action

![image](https://github.com/user-attachments/assets/3539ef87-8bce-436c-a826-fbdc4a7da526)

Runs [pglockanalyze](https://crates.io/crates/pglockanalyze) against a PR with one
or more migration files and reports the results in the diff.

## Usage

You have to bring your own `postgres:` service container (any version), specify the
connection parameters and the action executes pglockanalyze against it, using
the files you provided.

Also, you have to make sure to provision the database so that it's in a proper
state for the analysis to be possible (e.g. if you have pre-existing migrations
that should not be analyzed, you are responsible for running them).

See https://github.com/agis/pglockanalyze-action/pull/5 for a sample PR demonstrating how one might use this action.

## Status

This software is in *alpha* stage - *expect breakage* and rough edges.

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `input_files` | **yes** | — | Newline-separated list of migration files to analyse, relative to the repo root. |
| `pgla-version` | no | latest | Version of pglockanalyze to use |
| `cli-flags` | no | — | Extra flags to pass to pglockanalyze |
| `db-host` | no | `localhost` | Host used in the connection string |
| `db-port` | no | `5432` | Port number. |
| `db-name` | no | `pgladb` | Database to create/use for analysis |
| `db-user` | no | `pglauser` | Role created for the run |
| `db-password` | no | `pglapass` | Password for `db-user` |

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

      # ...run pre-existing migrations here...

      - uses: agis/pglockanalyze-action@v1
        with:
          # List of migration files to analyze
          input_files: |
            migrations/20240525_add_name_to_users.sql
            migrations/20240525_drop_cars.sql
