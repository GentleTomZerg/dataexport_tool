# Demo Config

This directory is meant for manual checking of `exportctl.sh`.

Files:

- `db.properties`: two DB profiles, `primary` and `reporting`
- `jobs.properties`: jobs covering success, date variables, compression, transfer, alternate DB type, and invalid config
- includes a MySQL split-column example via `job.article_body.SPLIT.body=4000,3`
- `env.properties`: output roots used by the demo jobs
- `pwd/`: demo password-key location used by DB profile configuration

Useful commands:

```bash
bash script/bin/exportctl.sh validate \
  --db-config script/etc/demo/db.properties \
  --jobs-config script/etc/demo/jobs.properties \
  --env-config script/etc/demo/env.properties

bash script/bin/exportctl.sh plan \
  --db-config script/etc/demo/db.properties \
  --jobs-config script/etc/demo/jobs.properties \
  --env-config script/etc/demo/env.properties \
  --date 2026-03-17 \
  users article_body invalid_unknown_profile

bash script/bin/demo_exportctl.sh
```

Expected behavior:

- invalid jobs are logged with `JOB_FAIL`
- valid jobs still continue
- process exit is `0` unless CLI arguments are invalid
