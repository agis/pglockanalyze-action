# pglockanalyze-action

<p align="center">
  <img src="https://github.com/user-attachments/assets/3539ef87-8bce-436c-a826-fbdc4a7da526" />
</p>

Runs [pglockanalyze](https://github.com/agis/pglockanalyze) against a PR with one
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
| `input_files` | no* | — | Newline-separated list of migration files to analyse, relative to the repo root. *Required if `migration-path` is not provided. |
| `migration-command` | no | — | Command to run existing migrations before analysis. Required when using `migration-path`. |
| `migration-path` | no | — | Path or glob pattern where migration files reside. When provided, automatically detects new migration files. |
| `pgla-version` | no | latest | Version of pglockanalyze to use |
| `cli-flags` | no | — | Extra flags to pass to pglockanalyze |
| `db-host` | no | `localhost` | Host used in the connection string |
| `db-port` | no | `5432` | Port number. |
| `db-name` | no | `pgladb` | Database to create/use for analysis |
| `db-user` | no | `pglauser` | Role created for the run |
| `db-password` | no | `pglapass` | Password for `db-user` |

## Usage Modes

### Manual Mode (Original)
Specify exactly which migration files to analyze using `input_files`. You are responsible for setting up the database state.

### Automatic Mode (New)
Use `migration-path` and `migration-command` to let the action automatically:
1. Detect new migration files in your PR
2. Run existing migrations to set up the database
3. Analyze only the new migration files

---

## Examples

### Manual Mode (Original)

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
```

### Automatic Mode

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
        with:
          fetch-depth: 0  # Need full history to detect new files

      - uses: agis/pglockanalyze-action@v1
        with:
          migration-path: "migrations"
          migration-command: "your-migration-tool up"  # e.g., "migrate -path migrations -database $DATABASE_URL up"
```
