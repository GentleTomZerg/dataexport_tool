# Data Exporter Design Summary

## Goals

- Support multiple export jobs in a single config.
- Separate DB profile config from export job config.
- Provide modular, testable shell libraries
- Default DB type is MySQL.
- Default mode prints SQL only (use `--execute` to run).

## Modules (lib/)

- `lib/properties.sh`
  - Loads `.properties` into an associative map.
  - Merges into the existing `PROPS` map (does not clear it).
  - Expands `${VAR}` placeholders using env vars and other properties (including dotted keys).
- `lib/db_config.sh`
  - Loads DB profile (host/port/name/user/type).
  - Builds password file path `{host}_{port}_{user}.pwd`.
  - All DB profile fields are required (including `DB_TYPE` and password settings).
- `lib/crypto.sh`
  - Encrypt/decrypt passwords using `openssl` and `DB_PASSWORD_KEY_FILE` (path to key file).
  - `write_db_password_file` writes the profile-based `{host}_{port}_{user}.pwd`.

## Toolkit

- `bin/password_tool.sh`
  - Encodes and writes a profile-based password file under `<profile>.DB_PASSWORD_DIR`.
- `lib/job_config.sh`
  - Loads a single job config and its filters from `export_jobs.properties`.
  - Loads optional field/line separators (defaults: `\t`, `\n`).
  - Loads optional split-column rules (Option B: `job.<name>.SPLIT.<col>=<chunk_size>,<chunks>`).
  - Loads optional post-export settings for compression and transfer.
- `lib/post_export.sh`
  - Optional post-export processing: compress and/or move/copy artifacts.
- `lib/sql_builder.sh`
  - Builds a `SELECT` with filters, supports `BETWEEN`.
  - For MySQL only, can expand TEXT columns into chunked `SUBSTRING` pieces and omit the original column.
- `lib/sql_exec.sh`
  - SQL executor (mysql default, postgres supported). Uses password file if present. Not used in default flow.
  - Output formatting rewrites tab-separated results to custom separators via `awk`.

## Entry Points

- `bin/export_data.sh`
  - Loads DB and job configs.
  - Expands runtime date variables.
  - Builds SQL and prints it per job.
  - `--execute` runs `lib/sql_exec.sh` and writes export files.
  - Requires `--db-config` and `--jobs-config`.
  - Each job must set `job.<name>.DB_PROFILE`.

## Config Files

### `etc/local/env.properties` (ENV_* variables)

```
ENV_WORK_PATH=/nas/lens_scripts
ENV_GTP_TEMP_PATH=/nas/gtpdata/temp
ENV_EDP_OUT_PATH=/nas/gtpdata/edp/out
ENV_EDP_IN_PATH=/nas/gtpdata/edp/in
```

### `etc/local/config/export_jobs.properties` (multi-job export)

```
primary.DB_HOST=localhost
primary.DB_PORT=3306
primary.DB_NAME=example_db
primary.DB_USER=example_user
primary.DB_TYPE=mysql
primary.DB_PASSWORD_DIR=./etc/local/pwd
primary.DB_PASSWORD_KEY_FILE=./etc/local/pwd/key_file

job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name,email,created_at
job.users.EXPORT_FILE=./exports/${job.users.TABLE_NAME}_${EXPORT_DATE}.csv
job.users.FIELD_SEPARATOR=|
job.users.LINE_TERMINATOR=\n
job.users.FILTER.status=active
```

### DB Config Format

Required per profile:
- `<profile>.DB_HOST`
- `<profile>.DB_PORT` (numeric)
- `<profile>.DB_NAME`
- `<profile>.DB_USER`
- `<profile>.DB_TYPE` (`mysql` or `postgres`)
- `<profile>.DB_PASSWORD_DIR` (directory containing encrypted .pwd files)
- `<profile>.DB_PASSWORD_KEY_FILE` (key file path used by openssl)

Optional:
- None. All fields are required.

Defaults:
- None. All fields must be provided by the user.

### Job Config Format

Required per job:
- `job.<name>.DB_PROFILE`
- `job.<name>.TABLE_NAME`
- `job.<name>.COLUMNS` (comma-separated, no empty entries)

Optional:
- `job.<name>.EXPORT_FILE`
- `job.<name>.FIELD_SEPARATOR` (default: `\t`)
- `job.<name>.LINE_TERMINATOR` (default: `\n`)
- `job.<name>.FILTER.*`
- `job.<name>.SPLIT.<col>=<chunk_size>,<chunks>`
- `job.<name>.COMPRESS.*`
- `job.<name>.TRANSFER.*`

Defaults:
- `job.<name>.EXPORT_FILE` can be omitted when not using `--execute` (SQL-only mode).
- `job.<name>.FIELD_SEPARATOR` defaults to `\t`.
- `job.<name>.LINE_TERMINATOR` defaults to `\n`.

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

Set by `bin/export_data.sh`:

- `${EXPORT_DATE}` (default today or `--date`)
- `${TODAY}` (alias of `EXPORT_DATE`)
- `${YESTERDAY}`
- `${EXPORT_MONTH}` (YYYY-MM)
- `${MONTH_START}` (YYYY-MM-01)
- `${MONTH_END}` (last day of month)

## Platform Notes

- Scripts require `bash` (associative arrays, `[[ ]]`, and `extglob` are used).
- `bin/export_data.sh` depends on GNU `date` (`date -d`).
- `openssl`, `mysql`, and `psql` are required only when those code paths are used.

## Usage

### Common commands

- SQL-only (default):
  `bash bin/export_data.sh --db-config etc/local/config/export_jobs.properties --jobs-config etc/local/config/export_jobs.properties --env-config etc/local/env.properties`
- Execute exports:
  `bash bin/export_data.sh --db-config etc/local/config/export_jobs.properties --jobs-config etc/local/config/export_jobs.properties --env-config etc/local/env.properties --execute`
- Run a single job:
  `bash bin/export_data.sh --db-config etc/local/config/export_jobs.properties --jobs-config etc/local/config/export_jobs.properties --env-config etc/local/env.properties --job users --date 2026-03-17`

Notes:
- `--db-config` and `--jobs-config` currently point to the same file since DB profiles and jobs live together.
- `--env-config` is optional and only needed if `ENV_*` variables are referenced in the config.

Print SQL for all jobs:

```
./bin/export_data.sh --db-config ./etc/local/env.properties --jobs-config ./etc/local/config/export_jobs.properties
```

Print SQL for specific jobs:

```
./bin/export_data.sh --db-config ./etc/local/env.properties --jobs-config ./etc/local/config/export_jobs.properties --jobs users,orders --date 2026-03-17
```

Execute exports for specific jobs:

```
./bin/export_data.sh --db-config ./etc/local/env.properties --jobs-config ./etc/local/config/export_jobs.properties --jobs users,orders --date 2026-03-17 --execute
```

## Exit Codes

- Exit `1` (global failure):
  - Missing required CLI flags (`--db-config`, `--jobs-config`)
  - DB config file not found or unreadable
  - Jobs config file not found or unreadable
  - No jobs resolved
  - Runtime date computation failure
- Exit `0` (job failures do not stop the run):
  - Job validation failure
  - Missing `EXPORT_FILE` when `--execute`
  - SQL execution failure
  - Compression failure
  - Transfer failure
  - DB profile invalid for a specific job

## Passwords

- Password files are named `{DB_HOST}_{DB_PORT}_{DB_USER}.pwd` under `DB_PASSWORD_DIR`.
- Encryption/decryption uses `openssl des3 ... -pbkdf2 -iter 100000` with a key file (`DB_PASSWORD_KEY_FILE`).
- Use the toolkit entry to generate password files:

```
bin/password_tool.sh --db-props etc/local/env.properties --db-profile primary --password '...' --key-file /path/to/keyfile
```

## Tests Added

- `test/crypto_test.sh` (fake `openssl` arg checks)
- `test/sql_exec_test.sh` (fake `mysql`/`psql`, separators, password file usage)
- `test/export_exec_test.sh` (end-to-end `--execute` wiring)

## Shell Compatibility

- Bash only (not POSIX `sh`).

## Split Columns (MySQL Only)

Use this when a TEXT column is too large and you need fixed-size chunks.
Only applies to MySQL; other DB types ignore the split rules.

Config (Option B):

```
job.users.SPLIT.content=4000,3
```

Behavior:
- `content` will be replaced with:
  - `SUBSTRING(content, 1, 4000) AS content_part1`
  - `SUBSTRING(content, 4001, 4000) AS content_part2`
  - `SUBSTRING(content, 8001, 4000) AS content_part3`
- The original `content` column is not selected.
- If the column is longer than the configured chunks, the rest is dropped.

## Post-Export: Compression and Transfer

Optional per-job settings:

```
job.<name>.COMPRESS.ENABLED=true|false
job.<name>.COMPRESS.MODE=gz|tar|tar.gz|tgz
job.<name>.COMPRESS.OVERWRITE=true|false
job.<name>.COMPRESS.REMOVE_ORIGINAL=true|false

job.<name>.TRANSFER.ENABLED=true|false
job.<name>.TRANSFER.DIR=/path/to/transfer
job.<name>.TRANSFER.MODE=move|copy
job.<name>.TRANSFER.OVERWRITE=true|false
job.<name>.TRANSFER.RENAME=${JOB_NAME}_${EXPORT_DATE}${EXT}
```

Behavior:
- Compression happens before transfer.
- If compression is enabled, the artifact becomes the compressed output.
- Transfer moves/copies the final artifact into `TRANSFER.DIR`.
- Rename supports `${JOB_NAME}`, `${EXPORT_DATE}`, `${BASENAME}`, `${EXT}`.
