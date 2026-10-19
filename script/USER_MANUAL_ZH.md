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
job.users.FIELD_SEPARATOR_DATA_REPLACEMENT=|?
```

### 5.3 文件拆分示例（FILE_SPLIT）

按大小把导出行集合切成多个 gz part：

```properties
job.events_split.DB_TYPE=${ENV_LENS_MNGT_TDSQL_TYPE}
job.events_split.DB_HOST=${ENV_LENS_MNGT_TDSQL_HOST}
job.events_split.DB_PORT=${ENV_LENS_MNGT_TDSQL_PORT}
job.events_split.DB_NAME=${ENV_LENS_MNGT_TDSQL_NAME}
job.events_split.DB_USER=${ENV_LENS_MNGT_TDSQL_USER}
job.events_split.DB_PASSWORD_FILE=${ENV_LENS_MNGT_TDSQL_PASSWORD_FILE}
job.events_split.DB_PASSWORD_KEY_FILE=${ENV_LENS_MNGT_TDSQL_PASSWORD_KEY_FILE}
job.events_split.TABLE_NAME=user_events
job.events_split.COLUMNS=id,user_id,event_type,created_at
job.events_split.WHERE=created_at >= '${MONTH_START}'
job.events_split.EXPORT_FILE=${ENV_GTP_TEMP_PATH}/${PART}-LENS-${job.events_split.TABLE_NAME}-${EXPORT_DATE}-2G
job.events_split.COMPRESS.ENABLED=true
job.events_split.COMPRESS.MODE=gz
job.events_split.FILE_SPLIT.ENABLED=true
job.events_split.FILE_SPLIT.MAX_SIZE=2G
job.events_split.FILE_SPLIT.INDEX_WIDTH=2
job.events_split.TRANSFER.ENABLED=true
job.events_split.TRANSFER.DIR=${ENV_EDP_OUT_PATH}
job.events_split.TRANSFER.MODE=copy
job.events_split.TRANSFER.RENAME=${PART}-LENS-${job.events_split.TABLE_NAME}-${EXPORT_DATE}-2G.${job.events_split.COMPRESS.MODE}
```

详见 [6.4 文件拆分](#64-文件拆分file_split)。

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
| `job.<name>.FIELD_SEPARATOR_DATA_REPLACEMENT` | `\|?` | 将字段数据中的 `\|!` 替换为该值（防止与分隔符冲突） |
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
| `job.<name>.FILE_SPLIT.ENABLED` | `false` | 是否启用文件拆分（按大小切多个 part） |
| `job.<name>.FILE_SPLIT.MAX_SIZE` | 无（启用时必填） | 每个 part 的 gz 大小上限；支持 `K/M/G`（1024 进制）或纯字节数 |
| `job.<name>.FILE_SPLIT.INDEX_WIDTH` | `2` | 序号位数，零填充，从 `00` 起自增 |

`job.<name>.FIELD_SEPARATOR_DATA_REPLACEMENT` 为非必填项，未配置时默认值为 `|?`。
该配置仅影响字段数据中的 `|!` 替换，不影响 `FIELD_SEPARATOR` 与 `LINE_TERMINATOR` 本身配置。

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

### 6.4 文件拆分（FILE_SPLIT）

文件拆分把一个 job 的行集合分散到多个 part 文件，每个 part 单独 gzip，part 名带零填充序号。它与 6.3 的**列拆分**（`SPLIT.<column>`，纵向加宽列）正交，可以同时启用。

启用后（默认关闭）：

- `EXPORT_FILE` 必须包含 `${PART}`，渲染为 `INDEX_WIDTH` 位零填充序号（`00`、`01`、…）。
- 必须 `COMPRESS.ENABLED=true` 且 `COMPRESS.MODE=gz`；`tar`/`tgz` 是归档容器，无法按字节切分，也不支持。
- 若 `TRANSFER.ENABLED=true`，`TRANSFER.RENAME` 必须包含 `${PART}`，否则各 part 会互相覆盖。
- `MAX_SIZE` 支持 `K/M/G`（1024 进制）后缀或纯字节数，必须 > 0；`INDEX_WIDTH` 必须是正整数。

不满足上述任一条件时，`validate`、`plan`、`run` 都会在构建计划阶段报错并停止该 job。

**模板变量 `${PART}`**

`${PART}` 在 `EXPORT_FILE` 与 `TRANSFER.RENAME` 中可用，渲染为按 `INDEX_WIDTH` 零填充的序号。它在 `EXPORT_FILE` 与 `TRANSFER.RENAME` 之外没有特殊含义，未启用拆分时保留字面量。

> 文件名里的 `1G`/`2G` 是**增量/全量的业务标记，与文件大小无关**，由配置人自行书写；工具不解析、不替换，只有 `MAX_SIZE` 才是真正的切分上限。

**计量口径：按压缩后的 gz 字节数**

每个 part 的 `.gz` 应 ≤ `MAX_SIZE`。由于 gz 是压缩产物、流式导出时无法预知大小，采用**两遍落地**：

1. Pass 1（导出）：沿用现有导出管道，把整份未压缩 CSV 落到 `EXPORT_FILE` 所在目录下的临时草稿目录（`mktemp -d` 生成的 `.file_split.<job>.XXXXXX/rows.csv`，同目录下另有 `.file-split-parts.XXXXXX` 临时切片目录），同时统计未压缩字节数与行数。
2. Pass 2（自适应切片）：读草稿，按上一片实测的压缩比校准预算，在**行边界**处切片，每个 part 单独 gzip 到 `render(EXPORT_FILE, ${PART})`。

草稿是工具内部产物，**不受 `COMPRESS.REMOVE_ORIGINAL` 管辖**；无论成功或失败，退出时都会删除该临时目录。

**切分与边界语义**

- **绝不从行中间切**：每片至少包含一行，因此单行超过 `MAX_SIZE` 时该 part 允许超限。
- **空结果**：仍产出 1 个空的 `00` part（保持“成功的 job 至少有一个 `00`”的不变量）。
- **超过位宽**：序号达到 `10^INDEX_WIDTH`（即需要第 `10^INDEX_WIDTH + 1` 份）时报错中止，提示调大 `INDEX_WIDTH`（不做动态加宽，避免同批文件名排序不一致）。

**`EXPORT_FILE` 是 part 路径模板本身**

拆分模式下，工具把每个 part 的 gzip 字节写到渲染后的 `EXPORT_FILE` 路径，**不会再追加 `.gz`**。因此如需 `.gz` 后缀，请在 `EXPORT_FILE`（或 `TRANSFER.RENAME`）模板里显式写出。

**陈旧 part 清理**

本次产出 N 份后，在**导出目录**内按该 job 渲染后的 part 名前缀，删除序号 ≥ N 的旧文件；**不清理 transfer 目录**（其内容由下游自动消费并删除）。

**传输与统计**

每个 part 各自走该 job 的 `TRANSFER.*` 配置，`RENAME` 中的 `${PART}` 逐个渲染。行数统计与不拆分时完全一致；日志区分 `bytes_csv`（未压缩，与今天同义）与 `bytes_gz`（各 part gz 之和），并逐 part 打印、汇总。

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
COLUMNS=id,name
EXPORT_FILE=./exports/users_2026-03-17.csv
FIELD_SEPARATOR=\t
LINE_TERMINATOR=\n
PASSWORD_FILE=/path/to/password.pwd
PASSWORD_KEY_FILE=/path/to/keyfile
FILE_SPLIT=disabled
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

启用文件拆分时，run 日志按 part 展开（`FILE_SPLIT=size=2G index_width=2 export_template=...`）：

```
[users] Export finished: file=... lines=1000 bytes_csv=40960
[users] Part ready: index=00 file=... lines=500 bytes_csv=20480 bytes_gz=5120
[users] Part ready: index=01 file=... lines=500 bytes_csv=20480 bytes_gz=5130
[users] Split finished: parts=2 lines=1000 bytes_csv=40960 bytes_gz=10250
[users] Final artifact ready: file=... bytes=5120
[users] Final artifact ready: file=... bytes=5130
[users] Completed successfully.
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
- 文件拆分要求 `COMPRESS.ENABLED=true` 且 `COMPRESS.MODE=gz`，不能与 `tar`/`tgz` 组合
- 文件拆分采用两遍落地，峰值临时空间约为“整份未压缩 CSV + 全部 part gz”
