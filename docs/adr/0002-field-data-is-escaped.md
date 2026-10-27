# Field data is escaped at the database client, not replaced

A tab, newline or carriage return inside a column's data must not be able to impersonate the format's structure: a row has to stay one line, and a row's field count has to stay fixed. We keep that guarantee by **escaping** the data — a tab leaves as the two bytes `\t`, a newline as `\n`, a backslash as `\\` — and require consumers to unescape. We deliberately do not substitute a placeholder token for these characters, and we do not rewrite them in SQL.

This costs us backwards compatibility in one direction: `mysql` is no longer called with `--raw`, so every job's artifact changes for rows that contain a tab, newline or backslash, and each consumer must implement unescaping rather than merely stop splitting on tabs. It buys correctness: escaping is reversible, so no data is lost, and it is the format both database clients already emit (`mysql --batch` escapes NUL/tab/LF/backslash; `COPY ... FORMAT text` escapes tab/LF/CR/backslash). The whole change is one flag removed in `db.sh`.

## Considered Options

- **B. Replace each colliding character with a configured token**, extending the existing `FIELD_SEPARATOR_DATA_REPLACEMENT` (`|!` → `|?`) precedent. Nothing downstream needs to learn to unescape, but the substitution is lossy and silent: the original tab is gone forever, and nobody notices until a report is wrong.
- **C. Scrub in SQL** (`REPLACE(col, CHAR(9), ' ')`) via `COLUMNS`. No pipeline change, but it must be repeated per column, breaks the comma-splitting that `SPLIT.<column>` relies on, cannot cover `SELECT *`, and still can't be enforced.
- **A. Escape at the client (chosen).**

## Consequences

- A consumer that does not unescape sees `\\t` where data held a literal `\t`; unescaping must be done `\\` first, then `\t`/`\n`/`\r`. This is a migration item per job, not a no-op.
- There is no per-job switch: every job's artifact format changes at once. A switch was rejected because two artifact formats in flight is a worse trap than one migration.
- CR is **not** escaped. `mysql --batch` writes CR raw whether or not `--raw` is given: `tee_write` only handles `\t`, `\n` and `\\`, despite the `MY_PRINT_CTRL` comment claiming CR too. CR is neither the field separator nor the record separator, so it cannot corrupt structure; it passes through untouched, while postgres emits `\r`. Accepted as a known limitation rather than adding an awk escape pass for a byte that breaks nothing — reconsider if a downstream consumer treats CR as significant.
- The postgres branch needs no change — `COPY ... FORMAT text` already conforms — and remains without automated tests.
- The `NULL` marker is out of scope and still ambiguous on mysql: a real NULL and the literal text `'NULL'` are indistinguishable in batch output (issue `04`).
