# Refactor Context

## Current State

The project has been rewritten around `script/bin/exportctl.sh`.

Current behavior:

- `validate`: parse config, resolve runtime/env values, build each job plan, print `STATUS=OK` or `STATUS=FAILED`
- `plan`: print runtime, `ENV_*`, per-job plan details, and SQL
- `run`: print plan details, execute export, run artifact pipeline, and log stage-level progress

Current exit behavior:

- exit `1` only for invalid CLI arguments
- runtime failures log errors but still return `0`

## Ownership Decisions

The recent refactor intentionally moved orchestration concerns into `script/bin/exportctl.sh`.

Things now owned by `exportctl`:

- CLI argument parsing
- runtime date calculation
- `ENV_*` export and printing
- selector resolution
- batch summary bookkeeping and printing
- mode dispatch for validate / plan / run

Things still kept in libraries:

- properties parsing and expansion: `script/lib/config/properties.sh`
- job loading: `script/lib/export/job.sh`
- DB profile loading: `script/lib/export/profile.sh`
- normalized plan building: `script/lib/export/plan.sh`
- SQL rendering: `script/lib/sql/render.sh`
- DB execution: `script/lib/exec/db.sh`
- artifact handling: `script/lib/artifact/pipeline.sh`

## Important Simplifications Already Made

- removed the old multi-script structure and rebuilt the tool around `exportctl`
- removed `password encode|decode` from `exportctl`
- removed group-based job selectors
- removed the separate selector module
- removed the separate summary module
- removed the separate args module
- removed the separate runtime module
- removed the `EXT` rename placeholder
- restored MySQL split-column support via `job.<name>.SPLIT.<column>=<chunk_size>,<chunks>`
- separated `validate` and `plan` output behavior

## Current Logging Model

Per-job logs:

- `JOB_INFO`
- `JOB_OK`
- `JOB_FAIL`

Current detailed runtime logs in `run` mode include:

- export start
- export success with file, line count, byte size
- compress start / success
- transfer start / success
- final artifact path and size

Final batch output:

- `SUMMARY total=... ok=... failed=...`
- `FAILED_JOBS=...` when applicable

## Known Constraints

- `WHERE` is raw SQL passthrough
- only `mysql` and `postgres` are supported
- split-column rendering currently only applies to MySQL
- property expansion only sees explicitly defined properties and exported variables
- if a rename template references something like `${job.finance.COMPRESS.MODE}`, that property must actually be defined in config
- `exportctl` is intentionally limited to `validate`, `plan`, and `run`

## Recent Structural Cleanup

`script/bin/exportctl.sh` has been improved by:

- introducing an explicit CLI context map instead of file-level `CLI_*` globals
- removing the fake runtime parameter from `build_export_plan`
- splitting the old large `process_job` flow into:
  - `build_job_plan`
  - `handle_validate_mode`
  - `handle_plan_mode`
  - `handle_run_mode`

## What Still Needs Improvement

High priority:

- keep reducing the size and cognitive load of `script/bin/exportctl.sh`
- tighten naming and section ordering in `script/bin/exportctl.sh`
- review ShellCheck warnings, especially around `local -A`, namerefs, and orchestration helpers

Medium priority:

- decide whether some helper functions inside `exportctl` should become very small local utility libraries again, but only if they are truly generic and reused
- improve the transfer rename model if richer current-job placeholders are needed
- make demo/sample config internally consistent where rename patterns reference compression settings

Low priority:

- expand the user manual further if operator guidance needs troubleshooting / FAQ sections
- consider whether final summary output should stay plain stdout or move to the same structured logging style

## Recommended Next Steps

1. Clean up `script/bin/exportctl.sh` naming and section ordering.
2. Run a focused ShellCheck pass and fix only real issues.
3. Decide whether to keep summary helpers exactly as-is or simplify them further.
4. Review sample configs under `script/etc/demo` and `script/etc/local`.

## Verification Command

Use this as the baseline regression check:

```bash
bash script/test/run_all.sh
```
