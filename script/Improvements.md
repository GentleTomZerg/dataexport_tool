# Improvements

## Overview

This document captures improvement ideas identified during a code review of the `script/` directory. Items are grouped by category and ordered roughly by impact.

---

## Code Duplication

### 1. Extract shared test helpers

Every test file (`properties_test.sh`, `db_config_test.sh`, `crypto_test.sh`, etc.) redefines `assert_eq`, `assert_true`, and `assert_fail`. That's ~180 lines of copy-paste across 9 files.

**Fix**: Create `test/test_helpers.sh` and source it from each test.

### 2. Deduplicate `_sql_trim`

`lib/sql_builder.sh:9-14` duplicates `trim()` from `lib/properties.sh`. The logic is identical.

**Fix**: Source `properties.sh` from `sql_builder.sh`, or extract `lib/common.sh` for shared utilities.

### 3. Simplify SQL execution password branching

`lib/sql_exec.sh:42-65` (`_sql_exec_with_mysql`) and `lib/sql_exec.sh:67-91` (`_sql_exec_with_postgres`) duplicate the entire DB command invocation, differing only in how the password env var is set.

**Fix**: Normalize the env var upfront so the command runs once:
```bash
local env_prefix=""
[[ -n "$db_password" ]] && env_prefix="MYSQL_PWD=$db_password"
eval "$env_prefix" mysql --batch --raw ...
```

### 4. Extract boolean validation helper

`job_config.sh:186-214` (`validate_job_compress`) and `job_config.sh:126-150` (`validate_job_transfer`) both repeat the same `case` pattern for `true|false`.

**Fix**:
```bash
_validate_bool() { case "$2" in true|false) ;; *) echo "Invalid $1 for job: ..." >&2; return 1;; esac; }
```

---

## Security

### 5. Upgrade from DES3 to AES-256

`lib/crypto.sh:27` uses `openssl des3` — a deprecated cipher that is slower and weaker than modern alternatives.

**Fix**:
```bash
openssl enc -aes-256-cbc -salt -in "$pwd_file" -pass "file:$DB_PASSWORD_KEY_FILE" -pbkdf2 -iter 100000
```

### 6. Strengthen SQL literal escaping

`sql_builder.sh:16-19` only escapes `'` → `''`. If filter values come from user input, backslash, null bytes, and other characters are not handled.

**Fix**: Add backslash escaping at minimum. Consider validating that filter values don't contain control characters.

---

## Code Clarity

### 7. Break up `run_jobs`

`export_data.sh:193-287` handles validation, SQL building, execution, compression, and transfer in a single 90-line loop body with multiple `failed_jobs+=` / `continue` blocks.

**Fix**: Extract helper functions:
```bash
_run_single_job() {
  validate_job_bundle "$job"   || return 1
  _resolve_db_profile "$job"   || return 1
  _print_job_info "$job"
  [[ "$EXECUTE" -eq 1 ]]       || return 0
  _execute_job "$job"           || return 1
  _post_process_job "$job"      || return 1
}
```

### 8. Merge filter load and validate

`job_config.sh` splits filter handling into `load_job_filters` and `validate_job_filters`. If `.from`/`.to` are empty, the load phase still adds a partial entry. The caller must remember to call both in the right order.

**Fix**: Consider merging load+validate into a single function, or make `validate_job_filters` the single source of truth that also populates `JOB_FILTERS`.

### 9. Replace pipe-delimited pseudo-structs

`JOB_FILTERS` and `JOB_SPLITS_RAW` store data as `"col|op|value"` strings. This is fragile if any value ever contains `|`. Positional meaning is implicit.

**Fix**: Use the ASCII Unit Separator (`$'\x1f'`) as delimiter — it's designed for field separation within records. Or use associative arrays keyed by column.

---

## Robustness

### 10. Regex in `expand_value` has imprecise dot matching

`lib/properties.sh:111`: The regex `\$\{[A-Za-z_][A-Za-z0-9_\\.]*\}` uses `\\.` inside a character class. The double-backslash is unnecessary there.

**Fix**: `\$\{[A-Za-z_][A-Za-z0-9_.]*\}` (single backslash) is correct and clearer.

### 11. Properties parser doesn't support multi-line values

`load_properties` in `properties.sh` treats each line as a standalone key=value. Multi-line values (e.g., SQL templates) are not supported.

**Consideration**: If multi-line is needed, support continuation lines ending with `\`.

### 12. `user_script.sh` hardcodes `FAKE_MYSQL=1`

`bin/user_script.sh:45` — this is left on by default, which would be a production hazard if deployed as-is.

**Fix**: Default to `0`, make opt-in via environment variable.

---

## Design

### 13. `--db-config` and `--jobs-config` are redundant

Both flags currently point to the same file (AGENTS.md:163). The naming implies separation but the implementation doesn't enforce it.

**Options**:
- Merge into a single `--config` flag.
- Or keep separate and add validation that DB profiles and job definitions are split correctly.

### 14. Add logging abstraction

Every module writes directly to stdout/stderr with raw `echo`. There's no way to control verbosity or add timestamps.

**Fix**: Create `lib/log.sh` with `log_info`, `log_warn`, `log_error` that support `--quiet` / `--verbose` modes.

### 15. Document global variable contracts

Modules communicate through `JOB_*` and `DB_*` globals implicitly. This is acceptable for shell scripts but not documented in code.

**Fix**: Add a header comment to each lib listing which globals it reads and writes.

---

## Priority

| Priority | Items |
|----------|-------|
| High | #5 (crypto), #6 (SQL escaping), #12 (FAKE_MYSQL default) |
| Medium | #1-4 (duplication), #7 (run_jobs clarity), #8 (filter load/validate) |
| Low | #9-11, #13-15 (design polish, edge cases) |
