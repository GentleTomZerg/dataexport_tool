# File-split limit is measured on the compressed artifact, not the source CSV

A file-split job caps each part at a configured size, and that cap is measured on the **gz** artifact the downstream consumer receives, not on the uncompressed CSV. Because gzip output size cannot be known while streaming, splitting runs as two passes: the export first lands a full intermediate CSV, then an adaptive pass slices it at line boundaries and gzips each slice, calibrating the uncompressed budget from the compression ratio observed on the previous part.

This deliberately gives up streaming — the whole intermediate CSV is written to temp — in exchange for staying dependency-free (bash + awk + gzip) and keeping the existing export pipeline and row-count statistics unchanged.

## Considered Options

- **A. Stream the CSV and rotate parts on live gzip output size.** Lowest disk, but plain `gzip` exposes neither an on-demand flush nor an accurate output size, so it needs a Perl/Python helper or a gzip coprocess driver. That is a new dependency and the heaviest part of the change.
- **C. Cap the uncompressed CSV instead.** Simplest and fully streaming, but each gz part lands at roughly 1/3–1/5 of the cap, multiplying the number of parts.
- **B. Two-pass, adaptive, gz-measured (chosen).**

## Consequences

- Peak temp usage is the full uncompressed CSV plus all part gz files (~10G for a 2G gz at a 4:1 ratio); the temp volume must have that headroom.
- `FILE_SPLIT` requires `COMPRESS.ENABLED=true` and `COMPRESS.MODE=gz`; `tar`/`tgz` cannot be split by size.
- Part sizes are near, not exactly, the cap: the first part uses a guessed ratio, and a single row larger than the cap is allowed to exceed it.
