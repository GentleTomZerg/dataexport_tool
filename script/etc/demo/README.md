# Demo Config

This directory is meant for manual checking of `exportctl.sh`.

Files:

- `jobs.properties`: jobs covering success, date variables, compression, transfer, column split, file split, an alternate DB type, and two intentionally-invalid jobs
- `env.properties`: DB connection and output roots used by the demo jobs
- `pwd/`: demo password-key location used by the jobs
- `db.properties`: kept as a tombstone; DB profiles were replaced by direct `DB_*` job fields

The file split example is `job.events_split`: it gzips `MAX_SIZE`-bounded parts and renders `${PART}` in both `EXPORT_FILE` and `TRANSFER.RENAME`. The `2G` in its name is a business marker, not a size.

Useful commands:

```bash
bash script/bin/exportctl.sh validate \
  --jobs-config script/etc/demo/jobs.properties \
  --env-config script/etc/demo/env.properties

bash script/bin/exportctl.sh plan \
  --jobs-config script/etc/demo/jobs.properties \
  --env-config script/etc/demo/env.properties \
  --date 2026-03-17 \
  users events_split invalid_split_tar

bash script/bin/demo_exportctl.sh
```

Expected behavior:

- `invalid_missing_db` and `invalid_split_tar` fail validation with a message naming the job and field
- valid jobs still continue and the process exit is `0` unless CLI arguments are invalid
- the file split job produces a gzipped `00-…` part (and `01-…`, `02-…` … once the data exceeds `MAX_SIZE`) and copies each part to the transfer directory
