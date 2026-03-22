# Agent Coding Guidelines

This is a Bash project for data export using `.properties` configuration files.

## Build/Test Commands

### Run All Tests
```bash
bash script/test/run_all.sh
```

### Run Single Test
```bash
bash script/test/properties_test.sh
bash script/test/selector_test.sh
bash script/test/plan_test.sh
bash script/test/exportctl_test.sh
```

### Package for Deployment
```bash
./make.sh
```

## Code Style Guidelines

### Shell Script Conventions

- **Shebang**: Use `#!/usr/bin/env bash` for all scripts
- **Shell Options**: Use `set -uo pipefail` and `shopt -s extglob` (see `lib/common/strict.sh`)
- **Path Resolution**: Use `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` for script-relative paths
- **Local Variables**: Always use `local` for function variables
- **References**: Use `local -n` for passing associative arrays by reference

### Function Naming

- Use snake_case: `load_export_profile`, `props_get`, `expand_value`
- Private helpers prefixed with `_` (if needed): Not used in this codebase
- Verbs for actions: `load_`, `get_`, `parse_`, `build_`, `render_`, `execute_`

### Variable Naming

- Associative arrays for maps: `local -A props=()` or `local -A plan=()`
- Use descriptive names: `db_profile`, `export_file`, `field_separator`
- Constants in UPPER_SNAKE: `EXPORT_DATE`, `YESTERDAY`
- Prefix config-related with source: `job.*`, `profile.*`, `ENV_*`

### Imports/Sourcing

```bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/properties.sh"
```

Use `source` for library loading. Use relative paths from script location.

### Error Handling

- Print errors to stderr: `printf 'ERROR: ...' >&2`
- Return `1` for failures, `0` for success
- Use `|| return 1` to propagate errors
- Log warnings but continue batch processing (return 0 even on runtime errors)

### Formatting

- Indent with 2 spaces (not tabs)
- Put function opening brace on same line: `func() {`
- Use `then`/`do` on same line with `if`/`for` when compact
- Separate functions with blank lines
- Maximum line length: ~120 chars

### Arrays and Maps

```bash
# Associative array
local -A props=()
props[key]="value"

# Nameref for passing
local -n _props="$props_name"

# Iterate over keys
for key in "${!_map[@]}"; do
```

### String Handling

- Use `[[ ]]` for conditionals (not `[ ]`)
- Use `printf '%s'` instead of `echo` for safety
- Use `${var:-default}` for defaults
- Use `${var//pattern/replacement}` for substitution

### Properties File Format

- Key-value separated by `=`
- Support `#` and `;` for comments
- Trim whitespace on both sides
- Tab-separated internally for parsing

### Exit Codes

- `1`: CLI argument errors only
- `0`: All runtime outcomes (failures logged, not exit codes)

## Project Structure

```
script/
├── bin/                    # Executable scripts
│   ├── exportctl.sh       # Main entry point
│   └── run_export.sh      # Simplified wrapper
├── lib/
│   ├── common/            # Shared utilities
│   │   └── strict.sh     # Shell setup
│   ├── config/            # Configuration handling
│   │   └── properties.sh # Properties parser
│   └── exportctl/
│       ├── model/         # Data models
│       │   ├── job.sh
│       │   ├── plan.sh
│       │   └── profile.sh
│       ├── run/           # Execution logic
│       │   ├── artifact.sh
│       │   ├── credentials.sh
│       │   ├── crypto.sh
│       │   └── db.sh
│       └── sql.sh         # SQL rendering
├── etc/
│   ├── demo/             # Demo configurations
│   ├── local/            # Local configurations
│   └── env.properties    # Environment variables
└── test/
    ├── run_all.sh        # Test runner
    ├── test_helpers.sh   # Test utilities
    └── *_test.sh         # Individual tests
```

## Common Patterns

### Passing Output Maps

```bash
local -A plan=()
build_export_plan "$props_name" "$job_name" profile job plan
```

### Checking Required Fields

```bash
if [[ -z "${_out[field]:-}" ]]; then
  printf 'ERROR: missing required field\n' >&2
  return 1
fi
```

### Default Values

```bash
[[ -n "${_out[separator]:-}" ]] || _out[separator]='\t'
```

### Error Propagation

```bash
load_props_from_file "$file" "props" || return 1
```
