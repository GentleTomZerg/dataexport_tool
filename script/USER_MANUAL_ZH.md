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

如需测试，可修改脚本顶部：

```bash
USE_FAKE_BIN=true  # 使用假的 mysql 输出
```

## 3. exportctl.sh 命令

### 3.1 validate

验证配置是否正确，不执行导出：

```bash
bash script/bin/exportctl.sh validate \
  --jobs-config FILE \
  --env-config FILE \
  [--date YYYY-MM-DD] \
  [job selectors...]
```

### 3.2 plan

显示解析后的执行计划，包含 SQL：

```bash
bash script/bin/exportctl.sh plan \
  --jobs-config FILE \
  --env-config FILE \
  [--date YYYY-MM-DD] \
  [job selectors...]
```

### 3.3 run

执行导出：

```bash
bash script/bin/exportctl.sh run \
  --jobs-config FILE \
  --env-config FILE \
  [--date YYYY-MM-DD] \
  [job selectors...]
```

## 4. 参数说明

### 4.1 `--jobs-config FILE`（必填）

Job 配置文件，包含 DB 连接和导出配置：

```properties
job.users.DB_TYPE=mysql
job.users.DB_HOST=localhost
job.users.DB_PORT=3306
job.users.DB_NAME=demo_db
job.users.DB_USER=demo_user
job.users.DB_PASSWORD_FILE=/path/to/password.pwd
job.users.DB_PASSWORD_KEY_FILE=/path/to/keyfile
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name,email
job.users.EXPORT_FILE=...
```

### 4.2 `--env-config FILE`（必填）

环境变量配置文件，用于变量展开：

```properties
ENV_WORK_PATH=/home/tom/Projects/dataexport
ENV_EDP_OUT_PATH=/home/tom/Projects/gtpdata/edp/out
ENV_GTP_TEMP_PATH=/home/tom/Projects/gtpdata/temp
```

### 4.3 `--date YYYY-MM-DD`（可选）

指定业务日期，会生成以下变量：

| 变量 | 格式 | 说明 |
|-----|------|------|
| `EXPORT_DATE` | `YYYY-MM-DD` | 传入的日期 |
| `TODAY` | `YYYY-MM-DD` | 同 EXPORT_DATE |
| `YESTERDAY` | `YYYY-MM-DD` | 业务日期前一天 |
| `EXPORT_MONTH` | `YYYY-MM` | 业务日期所在月份 |
| `MONTH_START` | `YYYY-MM-01` | 月首 |
| `MONTH_END` | `YYYY-MM-DD` | 月末 |
| `BJS_DATE` | `YYYYMMDD` | 无分隔符日期 |

### 4.4 `job selectors...`（可选）

指定只运行哪些 job：

```bash
bash script/bin/exportctl.sh run ... users orders
```

## 5. 配置示例

### 5.1 env.properties（环境变量）

```properties
ENV_WORK_PATH=/home/tom/Projects/dataexport
ENV_EDP_OUT_PATH=/home/tom/Projects/gtpdata/edp/out
ENV_GTP_TEMP_PATH=/home/tom/Projects/gtpdata/temp
```

### 5.2 jobs.properties（Job 配置 + DB）

```properties
job.users.DB_TYPE=${ENV_LENS_MNGT_TDSQL_TYPE}
job.users.DB_HOST=${ENV_LENS_MNGT_TDSQL_HOST}
job.users.DB_PORT=${ENV_LENS_MNGT_TDSQL_PORT}
job.users.DB_NAME=${ENV_LENS_MNGT_TDSQL_NAME}
job.users.DB_USER=${ENV_LENS_MNGT_TDSQL_USER}
job.users.DB_PASSWORD_FILE=${ENV_LENS_MNGT_TDSQL_PASSWORD_FILE}
job.users.DB_PASSWORD_KEY_FILE=${ENV_LENS_MNGT_TDSQL_PASSWORD_KEY_FILE}
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name,email
job.users.EXPORT_FILE=${ENV_GTP_TEMP_PATH}/users_${EXPORT_DATE}.csv
job.users.WHERE=create_at between ${YESTERDAY} and ${TODAY}
```

## 6. 配置字段参考

### 6.1 Job 必填字段

| 字段 | 说明 | 示例 |
|-----|------|------|
| `job.<name>.DB_TYPE` | 数据库类型 | `mysql` 或 `postgres` |
| `job.<name>.DB_HOST` | 数据库主机 | `localhost` |
| `job.<name>.DB_PORT` | 端口 | `3306` |
| `job.<name>.DB_NAME` | 数据库名 | `demo_db` |
| `job.<name>.DB_USER` | 用户名 | `demo_user` |
| `job.<name>.DB_PASSWORD_FILE` | 密码文件 | `./pwd/host_port_user.pwd` |
| `job.<name>.DB_PASSWORD_KEY_FILE` | 密钥文件 | `./pwd/keyfile` |
| `job.<name>.TABLE_NAME` | 表名 | `users` |
| `job.<name>.COLUMNS` | 列名 | `id,name,email` |
| `job.<name>.EXPORT_FILE` | 导出路径 | `./exports/users.csv` |

### 6.2 Job 可选字段及默认值

| 字段 | 默认值 | 说明 |
|-----|-------|------|
| `job.<name>.WHERE` | 空 | SQL 条件，原样拼入 |
| `job.<name>.FIELD_SEPARATOR` | `\t` | 字段分隔符 |
| `job.<name>.LINE_TERMINATOR` | `\n` | 行终止符 |
| `job.<name>.COMPRESS.ENABLED` | `false` | 是否启用压缩 |
| `job.<name>.COMPRESS.MODE` | `tar.gz` | 压缩格式：`gz`, `tar`, `tar.gz`, `tgz` |
| `job.<name>.COMPRESS.OVERWRITE` | `false` | 压缩文件存在时覆盖 |
| `job.<name>.COMPRESS.REMOVE_ORIGINAL` | `false` | 压缩后删除原文件 |
| `job.<name>.TRANSFER.ENABLED` | `false` | 是否启用传输 |
| `job.<name>.TRANSFER.DIR` | 空 | 传输目标目录 |
| `job.<name>.TRANSFER.MODE` | `move` | 传输模式：`copy` 或 `move` |
| `job.<name>.TRANSFER.OVERWRITE` | `false` | 目标文件存在时覆盖 |
| `job.<name>.TRANSFER.RENAME` | 空 | 目标文件名模板 |
| `job.<name>.SPLIT.<column>` | 无 | 列拆分：`chunk_size,chunks` |

### 6.3 列拆分说明

格式：`job.<name>.SPLIT.<column>=chunk_size,chunks`

示例：`job.users.SPLIT.blog=10000,3`

生成 SQL：
```sql
SELECT id,name,SUBSTRING(blog, 1, 10000) AS blog_part1,
       SUBSTRING(blog, 10001, 10000) AS blog_part2,
       SUBSTRING(blog, 20001, 10000) AS blog_part3,...
```

注意：被拆分的列必须已在 `COLUMNS` 中声明。仅 MySQL 支持。

## 7. 输出示例

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
== Job: users ==
DB_TYPE=mysql
DB_HOST=localhost
DB_PORT=3306
DB_NAME=demo
DB_USER=demo_user
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

## 8. 退出码

- 返回 `1`：命令行参数错误（缺少必填参数、日期格式错误等）
- 返回 `0`：其他所有情况（即使 job 失败）

## 9. 配置文件位置

| 配置文件 | 路径 |
|---------|------|
| Job 配置 | `etc/local/jobs.properties` |
| 环境变量 | `etc/env.properties` |

## 10. 测试验证

```bash
bash script/test/run_all.sh
```

## 11. 密码文件加密

密码文件使用 OpenSSL DES3 加密：

```bash
echo -n "my_password" | openssl des3 -salt -in /dev/stdin \
  -out /path/to/output.pwd \
  -pass file:/path/to/keyfile \
  -pbkdf2 -iter 100000
```

密码文件命名：`HOST_PORT_USER.pwd`，如 `localhost_3306_demo_user.pwd`

## 12. 限制

- `WHERE` 是原始 SQL，不做校验
- 只支持 `mysql` 和 `postgres`
- 列拆分仅对 MySQL 生效