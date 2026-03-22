# 数据导出工具使用手册

本文说明 `script/bin/exportctl.sh` 的使用方法。

## 1. 工具入口

有两层入口：

- `exportctl.sh` - 核心工具，支持 `validate`、`plan`、`run` 三种命令
- `run_export.sh` - 简化包装，配置硬编码，只需传日期

```bash
# 核心工具
bash script/bin/exportctl.sh <command> [options]

# 简化包装
bash script/bin/run_export.sh <date>
```

## 2. run_export.sh 快速使用

配置文件已硬编码在脚本内，只需传入日期：

```bash
bash script/bin/run_export.sh 2026-03-17
```

默认使用 `etc/local/` 下的配置。如需测试，可修改脚本顶部：

```bash
USE_FAKE_BIN=true  # 使用假的 mysql 输出
```

## 3. exportctl.sh 命令总览

### 3.1 validate

验证配置是否正确，不执行导出：

```bash
bash script/bin/exportctl.sh validate \
  --db-config FILE \
  --jobs-config FILE \
  [--env-config FILE] \
  [--date YYYY-MM-DD] \
  [job selectors...]
```

### 3.2 plan

显示解析后的执行计划，包含 SQL：

```bash
bash script/bin/exportctl.sh plan \
  --db-config FILE \
  --jobs-config FILE \
  [--env-config FILE] \
  [--date YYYY-MM-DD] \
  [job selectors...]
```

### 3.3 run

执行导出：

```bash
bash script/bin/exportctl.sh run \
  --db-config FILE \
  --jobs-config FILE \
  [--env-config FILE] \
  [--date YYYY-MM-DD] \
  [job selectors...]
```

## 4. 参数说明

### 4.1 `--db-config FILE`

数据库 profile 配置，格式：

```properties
<profile>.DB_HOST=...
<profile>.DB_PORT=...
<profile>.DB_NAME=...
<profile>.DB_USER=...
<profile>.DB_TYPE=mysql|postgres
<profile>.DB_PASSWORD_DIR=...
<profile>.DB_PASSWORD_KEY_FILE=...
```

### 4.2 `--jobs-config FILE`

Job 配置，格式：

```properties
job.<name>.DB_PROFILE=...
job.<name>.TABLE_NAME=...
job.<name>.COLUMNS=...
job.<name>.EXPORT_FILE=...
job.<name>.WHERE=...
```

### 4.3 `--env-config FILE`

环境变量配置，用于变量展开：

```properties
ENV_WORK_PATH=/path/to/work
ENV_EXPORT_ROOT=./exports
```

### 4.4 `--date YYYY-MM-DD`

指定业务日期，会生成以下变量：

- `EXPORT_DATE`
- `TODAY`
- `YESTERDAY`
- `EXPORT_MONTH`
- `MONTH_START`
- `MONTH_END`

### 4.5 `job selectors...`

可选，指定只运行哪些 job：

```bash
bash script/bin/exportctl.sh run ... users orders
```

## 5. 高级配置

### 5.1 列拆分（仅 MySQL）

拆分大字段为多列：

```properties
job.users.SPLIT.blog=10000,3
```

生成 SQL：

```sql
SELECT id,name,SUBSTRING(blog, 1, 10000) AS blog_part1,...
```

### 5.2 压缩配置

```properties
job.users.COMPRESS.ENABLED=true
job.users.COMPRESS.MODE=gz
job.users.COMPRESS.OVERWRITE=true
```

### 5.3 传输配置

```properties
job.users.TRANSFER.ENABLED=true
job.users.TRANSFER.DIR=${ENV_TRANSFER_ROOT}
job.users.TRANSFER.MODE=copy
job.users.TRANSFER.RENAME=users_${EXPORT_DATE}.gz
```

## 6. 输出示例

### validate 输出

```
== Runtime ==
EXPORT_DATE=2026-03-17
...

== Job: users ==
[users] Validation succeeded.
Summary: total=1 ok=1 failed=0
```

### plan 输出

```
== Runtime ==
...

== Job: users ==
DB_PROFILE=primary
DB_TYPE=mysql
TABLE=users
SQL=SELECT id,name FROM users WHERE status = 'active'
[users] Plan generated.
Summary: total=1 ok=1 failed=0
```

### run 输出

```
[users] Starting export: db_type=mysql file=./exports/users_2026-03-17.csv
[users] Export finished: file=... lines=100 bytes=1234
[users] Compressing artifact: ...
[users] Compression finished: ...
[users] Transferring artifact: ...
[users] Final artifact ready: file=... bytes=567
[users] Completed successfully.
Summary: total=1 ok=1 failed=0
```

## 7. 退出码

- 返回 `1`：命令行参数错误（缺少必填参数、日期格式错误等）
- 返回 `0`：其他所有情况（即使 job 失败）

## 8. 配置文件位置

| 配置文件 | 路径 |
|---------|------|
| 数据库配置 | `etc/local/db.properties` |
| Job 配置 | `etc/local/jobs.properties` |
| 环境变量 | `etc/env.properties` |

## 9. 测试验证

运行测试套件：

```bash
bash script/test/run_all.sh
```

## 10. 限制

- `WHERE` 是原始 SQL，不做校验
- 只支持 `mysql` 和 `postgres`
- 列拆分仅对 MySQL 生效
