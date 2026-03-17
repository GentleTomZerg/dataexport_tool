# Data Exporter Design Summary

## Goals

- Support multiple export jobs in a single config.
- Separate DB profile config from export job config.
- Provide modular, testable shell libraries
- Default DB type is MySQL.
- Current mode prints SQL only (no execution).

## Modules (lib/)

- `lib/properties.sh`
  - Loads `.properties` into an associative map.
  - Expands `${VAR}` placeholders using env vars and other properties (including dotted keys).
- `lib/db_config.sh`
  - Loads DB profile (host/port/name/user/type).
  - Builds password file path `{host}_{port}_{user}.pwd`.
  - Defaults `DB_TYPE=mysql` if not set.
- `lib/crypto.sh`
  - Encrypt/decrypt passwords using `openssl` and `DB_PASSWORD_KEY`.
- `lib/job_config.sh`
  - Loads a single job config and its filters from `data_export.properties`.
- `lib/sql_builder.sh`
  - Builds a `SELECT` with filters, supports `BETWEEN`.
- `lib/sql_exec.sh`
  - SQL executor (currently PostgreSQL only). Not used in default flow.

## Entry Points

- `data_export.sh`
  - Loads DB and job configs.
  - Expands runtime date variables.
  - Builds SQL and prints it per job.
  - No actual DB execution.

## Config Files

### `env.properties` (DB profiles)

```
primary.DB_HOST=localhost
primary.DB_PORT=3306
primary.DB_NAME=example_db
primary.DB_USER=example_user
primary.DB_TYPE=mysql
```

### `data_export.properties` (multi-job export)

```
JOBS=users,orders

job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name,email,created_at
job.users.EXPORT_FILE=./exports/${job.users.TABLE_NAME}_${EXPORT_DATE}.csv
job.users.FILTER.status=active
```

## Filters

- Basic: `job.<name>.FILTER.col=value` (defaults to `=`).
- Operator: `job.<name>.FILTER.col.op=LIKE` + `.value=%foo%`.
- BETWEEN:

```
job.<name>.FILTER.date.op=BETWEEN
job.<name>.FILTER.date.from=2024-01-01
job.<name>.FILTER.date.to=2024-01-31
```

## Runtime Date Variables

Set by `data_export.sh`:

- `${EXPORT_DATE}` (default today or `--date`)
- `${TODAY}` (alias of `EXPORT_DATE`)
- `${YESTERDAY}`
- `${EXPORT_MONTH}` (YYYY-MM)
- `${MONTH_START}` (YYYY-MM-01)
- `${MONTH_END}` (last day of month)

## Usage

Print SQL for all jobs:

```
./data_export.sh
```

Print SQL for specific jobs:

```
./data_export.sh --jobs users,orders --date 2026-03-17
```

## Shell Compatibility

- support sh
