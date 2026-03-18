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
  - Encrypt/decrypt passwords using `openssl` and `DB_PASSWORD_KEY_FILE` (path to key file).
  - `write_db_password_file` writes the profile-based `{host}_{port}_{user}.pwd`.

## Toolkit

- `tools/password_tool.sh`
  - Encodes and writes a profile-based password file under `DB_PASSWORD_DIR`.
- `lib/job_config.sh`
  - Loads a single job config and its filters from `export_jobs.properties`.
  - Loads optional field/line separators (defaults: `\t`, `\n`).
- `lib/sql_builder.sh`
  - Builds a `SELECT` with filters, supports `BETWEEN`.
- `lib/sql_exec.sh`
  - SQL executor (mysql default, postgres supported). Uses password file if present. Not used in default flow.

## Entry Points

- `export_data.sh`
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

### `export_jobs.properties` (multi-job export)

```
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name,email,created_at
job.users.EXPORT_FILE=./exports/${job.users.TABLE_NAME}_${EXPORT_DATE}.csv
job.users.FIELD_SEPARATOR=|
job.users.LINE_TERMINATOR=\n
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

Set by `export_data.sh`:

- `${EXPORT_DATE}` (default today or `--date`)
- `${TODAY}` (alias of `EXPORT_DATE`)
- `${YESTERDAY}`
- `${EXPORT_MONTH}` (YYYY-MM)
- `${MONTH_START}` (YYYY-MM-01)
- `${MONTH_END}` (last day of month)

## Usage

Print SQL for all jobs:

```
./export_data.sh
```

Print SQL for specific jobs:

```
./export_data.sh --jobs users,orders --date 2026-03-17
```

## Shell Compatibility

- support sh
