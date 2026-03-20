# 数据导出工具使用手册（中文）

## 1. export_data.sh 使用方法

### 基本用法

```bash
bash bin/export_data.sh \
  --db-config etc/local/config/export_jobs.properties \
  --jobs-config etc/local/config/export_jobs.properties \
  --env-config etc/local/env.properties \
  --date 2026-03-17
```

说明：
- `--db-config` 与 `--jobs-config` 当前指向同一个文件（DB profile + jobs）。
- `--env-config` 可选，仅当配置里使用 `ENV_*` 变量时需要。
- 不加 `--execute` 时只打印 SQL，不执行导出。

### 常用参数

- `--db-config <file>`：DB profile 配置文件（必需）
- `--jobs-config <file>`：Job 配置文件（必需）
- `--env-config <file>`：ENV_* 变量文件（可选）
- `--job <name>`：只跑单个 job
- `--jobs <a,b>`：只跑指定 jobs
- `--date <YYYY-MM-DD>`：运行日期（影响日期变量）
- `--execute`：执行导出并生成文件

## 2. 配置文件写法

### 2.1 `etc/local/env.properties`

只允许 `ENV_*` 变量：

```
ENV_WORK_PATH=/nas/lens_scripts
ENV_GTP_TEMP_PATH=/nas/gtpdata/temp
ENV_EDP_OUT_PATH=/nas/gtpdata/edp/out
ENV_EDP_IN_PATH=/nas/gtpdata/edp/in
```

### 2.2 `etc/local/config/export_jobs.properties`

此文件同时包含 **DB profile** 和 **Job** 配置。

#### DB profile（全部必填）

```
primary.DB_HOST=localhost
primary.DB_PORT=3306
primary.DB_NAME=example_db
primary.DB_USER=example_user
primary.DB_TYPE=mysql
primary.DB_PASSWORD_DIR=./etc/local/pwd
primary.DB_PASSWORD_KEY_FILE=./etc/local/pwd/key_file
```

必填项（每个 profile 都必须提供）：
- `<profile>.DB_HOST`
- `<profile>.DB_PORT`
- `<profile>.DB_NAME`
- `<profile>.DB_USER`
- `<profile>.DB_TYPE`（`mysql` 或 `postgres`）
- `<profile>.DB_PASSWORD_DIR`（加密密码文件目录）
- `<profile>.DB_PASSWORD_KEY_FILE`（openssl 密钥文件路径）

#### Job 配置（必填 + 可选）

**必填**
- `job.<name>.DB_PROFILE`
- `job.<name>.TABLE_NAME`
- `job.<name>.COLUMNS`

**可选**
- `job.<name>.EXPORT_FILE`（不执行时可省略）
- `job.<name>.FIELD_SEPARATOR`（默认 `\t`）
- `job.<name>.LINE_TERMINATOR`（默认 `\n`）
- `job.<name>.FILTER.*`
- `job.<name>.SPLIT.<col>=<chunk_size>,<chunks>`（MySQL）
- `job.<name>.COMPRESS.*`
- `job.<name>.TRANSFER.*`

示例（包含常用功能覆盖）：

```
# 基础过滤
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name,email,created_at
job.users.EXPORT_FILE=./exports/users_${EXPORT_DATE}.csv
job.users.FIELD_SEPARATOR=|
job.users.LINE_TERMINATOR=\n
job.users.FILTER.status=active
job.users.FILTER.created_at.op=>=
job.users.FILTER.created_at.value=2024-01-01

# BETWEEN
job.events.DB_PROFILE=primary
job.events.TABLE_NAME=events
job.events.COLUMNS=id,type,created_at
job.events.EXPORT_FILE=./exports/events_${EXPORT_DATE}.csv
job.events.FILTER.created_at.op=BETWEEN
job.events.FILTER.created_at.from=${EXPORT_DATE}
job.events.FILTER.created_at.to=${EXPORT_DATE}

# LIKE
job.customers.DB_PROFILE=primary
job.customers.TABLE_NAME=customers
job.customers.COLUMNS=id,name,email,created_at
job.customers.EXPORT_FILE=./exports/customers.csv
job.customers.FILTER.name.op=LIKE
job.customers.FILTER.name.value=%john%

# TEXT 分片（MySQL）
job.articles.DB_PROFILE=primary
job.articles.TABLE_NAME=articles
job.articles.COLUMNS=id,title,body,created_at
job.articles.EXPORT_FILE=./exports/articles_${EXPORT_DATE}.csv
job.articles.SPLIT.body=4000,3

# 压缩 + 传输
job.articles.COMPRESS.ENABLED=true
job.articles.COMPRESS.MODE=gz
job.articles.COMPRESS.OVERWRITE=true
job.articles.COMPRESS.REMOVE_ORIGINAL=true
job.articles.TRANSFER.ENABLED=true
job.articles.TRANSFER.DIR=${ENV_EDP_OUT_PATH}
job.articles.TRANSFER.MODE=move
job.articles.TRANSFER.OVERWRITE=true
job.articles.TRANSFER.RENAME=${JOB_NAME}_${EXPORT_DATE}.gz
```

### 2.3 运行时日期变量

由 `export_data.sh` 注入：
- `${EXPORT_DATE}`（默认今天或 `--date`）
- `${TODAY}`（同 EXPORT_DATE）
- `${YESTERDAY}`
- `${EXPORT_MONTH}`（YYYY-MM）
- `${MONTH_START}`（YYYY-MM-01）
- `${MONTH_END}`（当月最后一天）

## 3. 脚本与库的关系

### 3.1 总体流程

1. `bin/export_data.sh` 解析参数、加载 ENV、加载配置。
2. `lib/db_config.sh` 读取 DB profile，生成密码文件路径。
3. `lib/job_config.sh` 读取 job 配置、过滤条件、分片、压缩/传输设置。
4. `lib/sql_builder.sh` 根据 JOB_* 构造 SQL。
5. 若 `--execute`：
   - `lib/sql_exec.sh` 执行 SQL 并导出文件。
   - `lib/post_export.sh` 进行压缩与传输。

### 3.2 各库职责

- `lib/properties.sh`
  - 读取 `.properties` 到全局 `PROPS`。
  - 支持 `${VAR}` 占位符展开。
- `lib/db_config.sh`
  - 读取 DB profile。
  - 生成 `DB_PASSWORD_FILE`。
- `lib/job_config.sh`
  - 解析 job 配置、过滤、分片、压缩/传输参数。
- `lib/sql_builder.sh`
  - 生成 `SELECT ... WHERE ...` SQL。
- `lib/sql_exec.sh`
  - 执行 SQL（MySQL/Postgres）。
  - 如果存在密码文件，会尝试解密。
- `lib/crypto.sh`
  - 加密/解密密码文件（openssl）。
- `lib/post_export.sh`
  - 压缩文件、移动/复制文件。

## 4. 全局变量（关键）

### 4.1 运行时变量（export_data.sh）
- `EXPORT_DATE`, `TODAY`, `YESTERDAY`
- `EXPORT_MONTH`, `MONTH_START`, `MONTH_END`

### 4.2 DB 相关（db_config.sh）
- `DB_PROFILE`
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_TYPE`
- `DB_PASSWORD_DIR`（由 profile 配置提供）
- `DB_PASSWORD_FILE`
- `DB_PASSWORD_KEY_FILE`

### 4.3 Job 相关（job_config.sh）
- `JOB_NAME`
- `JOB_DB_PROFILE`, `JOB_TABLE`, `JOB_COLUMNS`
- `JOB_EXPORT_FILE`
- `JOB_FIELD_SEPARATOR`, `JOB_LINE_TERMINATOR`
- `JOB_FILTERS`（数组）
- `JOB_SPLITS`（数组）
- `JOB_COMPRESS_*` / `JOB_TRANSFER_*`

### 4.4 配置缓存（properties.sh）
- `PROPS`（全局关联数组）

