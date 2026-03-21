# TODO

## 1. Config validation improvements

### What must be fulfilled in the config properties

Current validation is inconsistent. Some required fields are checked, others are not.

**Required at load time (fail if missing):**
- `job.<name>.TABLE_NAME` — already checked
- `job.<name>.COLUMNS` — already checked
- `job.<name>.DB_PROFILE` — NOT checked (read but not validated)

**Required only for `--execute` mode:**
- `job.<name>.EXPORT_FILE` — checked at runtime, not at load time

**DB profile fields:**
- All 7 fields are required per profile — validated in `load_db_profile` (good)
- But there's no cross-job validation that the referenced `DB_PROFILE` exists at load time

**Questions to resolve:**
- Should `validate_job_config` also check that `DB_PROFILE` is non-empty?
- Should we validate that DB profile is defined before running jobs (early failure)?
- Should `WHERE` be required or optional? Currently optional — is that correct?

### Implementation plan
- Add `DB_PROFILE` check to `validate_job_config`
- Add a `validate_db_profile_exists` that checks the profile has all required keys
- Document clearly: which fields are required always, which only for `--execute`

---

## 2. Cleaner split implementation

### Current problems
- `JOB_SPLITS_RAW` is an intermediate array (load → raw → validate → final)
- Pipe-delimited strings `"col|chunk_size|chunks"` are opaque
- `validate_job_splits` re-parses the same data that `load_job_splits` already parsed
- The two-phase approach requires callers to call load + validate in order

### Possible improvements

**Option A: Merge load + validate into one function**
```bash
load_and_validate_job_splits() {
  # Load from PROPS, validate inline, produce JOB_SPLITS directly
  # No JOB_SPLITS_RAW intermediate step
}
```

**Option B: Use associative arrays instead of pipe-delimited strings**
```bash
declare -A JOB_SPLIT_size    # JOB_SPLIT_size[body]=4000
declare -A JOB_SPLIT_chunks  # JOB_SPLIT_chunks[body]=3
```
- Cleaner access in `sql_builder.sh`: `${JOB_SPLIT_size[$col]:-}`
- No string parsing on consumption side
- Matches the `JOB[]` / `JOB_TRANSFER[]` / `JOB_COMPRESS[]` pattern

**Option C: Validate at load time, skip separate validate function**
- `load_job_splits` validates inline and returns error on bad input
- Removes `validate_job_splits` entirely
- `validate_job_bundle` simplifies to: load → validate_config (no separate split validate)

### Recommendation
Option B + C: associative arrays for splits, validate inline at load time.

---

## 3. General: make load functions validate their own input

Pattern across job_config.sh:
- `load_*` functions read from PROPS but don't validate
- `validate_*` functions validate but re-read from PROPS
- Caller must remember to call both in order

**Better pattern:** each `load_*` function validates its own output before returning.
- `load_job_config` → validates columns, separators, DB_PROFILE
- `load_job_splits` → validates split values, column membership
- `load_job_transfer` → validates mode, overwrite
- `load_job_compress` → validates mode, overwrite

Then `validate_job_bundle` just calls `load_*` functions — no separate `validate_*` step.
