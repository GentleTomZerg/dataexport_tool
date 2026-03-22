# 数据导出工具使用手册

本文说明 `script/bin/exportctl.sh` 的所有参数、参数对应的配置文件含义、常见使用方式，以及完整示例。

## 1. 工具目标

这个项目的目标是：

- 从 `.properties` 文件读取数据库配置和导出任务配置
- 根据运行日期展开 `${EXPORT_DATE}`、`${YESTERDAY}` 等变量
- 为每个 job 生成 SQL
- 在 `run` 模式下执行导出
- 导出后可选压缩、复制或移动文件
- 即使部分 job 失败，也尽量继续执行其他 job

主入口：

```bash
bash script/bin/exportctl.sh ...
```

## 2. 命令总览

`exportctl.sh` 支持三类命令：

```bash
exportctl.sh validate ...
exportctl.sh plan ...
exportctl.sh run ...
```

它们的区别：

- `validate`
  读取配置、展开变量、解析 job、构建计划，但不执行数据库导出。
  只输出 job 是否可构建成功，不打印完整 SQL 细节。
- `plan`
  与 `validate` 类似，但会明确打印每个 job 的 SQL、导出目标和解析后的细节。
- `run`
  真正执行数据库导出，并触发压缩、传输等后处理。

## 3. 通用命令格式

### 3.1 `validate`

```bash
bash script/bin/exportctl.sh validate \
  --db-config FILE \
  --jobs-config FILE \
  [--env-config FILE] \
  [--date YYYY-MM-DD] \
  [job selectors...]
```

### 3.2 `plan`

```bash
bash script/bin/exportctl.sh plan \
  --db-config FILE \
  --jobs-config FILE \
  [--env-config FILE] \
  [--date YYYY-MM-DD] \
  [job selectors...]
```

### 3.3 `run`

```bash
bash script/bin/exportctl.sh run \
  --db-config FILE \
  --jobs-config FILE \
  [--env-config FILE] \
  [--date YYYY-MM-DD] \
  [job selectors...]
```

## 4. 所有参数的详细说明

下面按参数逐个说明。

### 4.1 `--db-config FILE`

作用：

- 指定数据库 profile 配置文件
- 文件里通常定义 `primary.DB_HOST`、`primary.DB_PORT` 这一类键

它指向什么：

- 一个 `.properties` 文件
- 里面以 `<profile>.DB_...` 的形式描述数据库连接信息

典型内容：

```properties
primary.DB_HOST=localhost
primary.DB_PORT=3306
primary.DB_NAME=demo_db
primary.DB_USER=demo_user
primary.DB_TYPE=mysql
primary.DB_PASSWORD_DIR=./script/etc/demo/pwd
primary.DB_PASSWORD_KEY_FILE=./script/etc/demo/pwd/key_file
```

使用场景：

- `job.users.DB_PROFILE=primary` 时，程序会去 `db-config` 里查 `primary` 这个 profile

注意：

- `--db-config` 是 `validate`、`plan`、`run` 的必填参数
- 如果参数本身缺失，命令行会直接退出 `1`
- 如果文件路径写了但文件不存在，会记录错误，但进程仍按项目约定返回 `0`

### 4.2 `--jobs-config FILE`

作用：

- 指定 job 配置文件
- 文件里定义每个导出任务的表、列、SQL 条件、输出文件等

它指向什么：

- 一个 `.properties` 文件
- 里面以 `job.<name>.*` 的形式描述每个 job

典型内容：

```properties
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name,email
job.users.EXPORT_FILE=./tmp/users_${EXPORT_DATE}.csv
job.users.WHERE=status = 'active'
```

使用场景：

- `exportctl` 会遍历这个文件里的所有 `job.<name>.*`
- 如果命令行指定了 selector，只执行匹配到的 job

注意：

- `--jobs-config` 是 `validate`、`plan`、`run` 的必填参数

### 4.3 `--env-config FILE`

作用：

- 指定环境变量配置文件
- 里面通常是 `ENV_` 开头的路径变量

它指向什么：

- 一个 `.properties` 文件
- 内容一般类似：

```properties
ENV_EXPORT_ROOT=./tmp/demo_exports
ENV_TRANSFER_ROOT=./tmp/demo_transfer
ENV_ARCHIVE_ROOT=./tmp/demo_archive
```

它怎么用：

- 如果 job 配置里写了 `${ENV_EXPORT_ROOT}`，程序会先读取 `--env-config`
- 然后把变量展开到最终值

例如：

```properties
job.users.EXPORT_FILE=${ENV_EXPORT_ROOT}/users_${EXPORT_DATE}.csv
```

展开后可能变成：

```text
./tmp/demo_exports/users_2026-03-17.csv
```

注意：

- `--env-config` 是可选参数
- 如果 job 里完全没有引用 `ENV_*` 变量，可以不传

### 4.4 `--date YYYY-MM-DD`

作用：

- 指定本次运行的业务日期
- 它不会改系统时间，只用于变量展开

格式要求：

- 必须是 `YYYY-MM-DD`
- 例如 `2026-03-17`

它会影响哪些变量：

- `EXPORT_DATE`
- `TODAY`
- `YESTERDAY`
- `EXPORT_MONTH`
- `MONTH_START`
- `MONTH_END`

例如传入：

```bash
--date 2026-03-17
```

则运行时变量通常会变成：

```text
EXPORT_DATE=2026-03-17
TODAY=2026-03-17
YESTERDAY=2026-03-16
EXPORT_MONTH=2026-03
MONTH_START=2026-03-01
MONTH_END=2026-03-31
```

典型使用：

```properties
job.daily_orders.WHERE=created_at BETWEEN '${YESTERDAY}' AND '${TODAY}'
job.audit.EXPORT_FILE=./archive/audit_${EXPORT_MONTH}.csv
```

如果不传：

- 默认使用当天日期

注意：

- 日期格式写错属于命令行参数错误，进程会退出 `1`

### 4.5 `job selectors...`

作用：

- 指定只运行哪些 job
- 放在命令最后，作为位置参数

当前只支持一种 selector：

- 直接写 job 名称

示例：

```bash
bash script/bin/exportctl.sh plan ... users
bash script/bin/exportctl.sh run ... users orders
```

#### 4.5.1 直接写 job 名

例如：

```bash
bash script/bin/exportctl.sh run ... users
```

表示：

- 只运行 `job.users.*` 这一组配置

如果 selector 不存在：

- 只记录错误日志
- 不会因为 unknown selector 直接退出

## 5. 配置文件写法详解

### 5.1 DB profile 配置

格式：

```properties
<profile>.DB_HOST=...
<profile>.DB_PORT=...
<profile>.DB_NAME=...
<profile>.DB_USER=...
<profile>.DB_TYPE=mysql|postgres
<profile>.DB_PASSWORD_DIR=...
<profile>.DB_PASSWORD_KEY_FILE=...
```

示例：

```properties
primary.DB_HOST=localhost
primary.DB_PORT=3306
primary.DB_NAME=demo_db
primary.DB_USER=demo_user
primary.DB_TYPE=mysql
primary.DB_PASSWORD_DIR=./script/etc/demo/pwd
primary.DB_PASSWORD_KEY_FILE=./script/etc/demo/pwd/key_file
```

字段解释：

- `DB_HOST`
  数据库主机名
- `DB_PORT`
  数据库端口
- `DB_NAME`
  数据库名
- `DB_USER`
  登录用户名
- `DB_TYPE`
  当前只支持 `mysql` 和 `postgres`
- `DB_PASSWORD_DIR`
  密码文件目录，由数据库执行层读取
- `DB_PASSWORD_KEY_FILE`
  密钥文件路径，由数据库执行层读取

### 5.2 Job 配置

格式：

```properties
job.<name>.DB_PROFILE=...
job.<name>.TABLE_NAME=...
job.<name>.COLUMNS=...
job.<name>.EXPORT_FILE=...
job.<name>.WHERE=...
```

最小可用示例：

```properties
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name,email
job.users.EXPORT_FILE=./tmp/users_${EXPORT_DATE}.csv
job.users.WHERE=status = 'active'
```

字段解释：

- `job.<name>.DB_PROFILE`
  指向 DB profile 名称，例如 `primary`
- `job.<name>.TABLE_NAME`
  最终 SQL 里的表名
- `job.<name>.COLUMNS`
  最终 SQL 里的列清单，原样拼到 `SELECT`
- `job.<name>.EXPORT_FILE`
  导出目标文件路径，可使用变量
- `job.<name>.WHERE`
  原样 SQL 条件，不做结构化解析
- `job.<name>.SPLIT.<column>`
  列拆分配置，格式是 `<chunk_size>,<chunks>`

注意：

- 当前设计明确保留 RAW `WHERE`
- 也就是你写什么，最终 SQL 就拼什么
- 因此这里需要你自己保证 SQL 条件合法

### 5.3 列拆分配置

这是你刚提到的能力，当前版本已经恢复。

使用方式：

```properties
job.article_body.DB_PROFILE=primary
job.article_body.TABLE_NAME=articles
job.article_body.COLUMNS=id,title,body,created_at
job.article_body.EXPORT_FILE=./tmp/articles_${EXPORT_DATE}.csv
job.article_body.WHERE=created_at >= '${MONTH_START}'
job.article_body.SPLIT.body=4000,3
```

含义：

- 对 `body` 这一列做拆分
- 每段长度 `4000`
- 总共拆成 `3` 段

当前实现方式：

- 只在 `mysql` 类型下生效
- SQL 会把原列改写成多个 `SUBSTRING(...) AS ...`

上面的配置最终会生成类似 SQL：

```sql
SELECT id,title,
SUBSTRING(body, 1, 4000) AS body_part1,
SUBSTRING(body, 4001, 4000) AS body_part2,
SUBSTRING(body, 8001, 4000) AS body_part3,
created_at
FROM articles
WHERE created_at >= '2026-03-01'
```

约束：

- 被拆分的列必须已经出现在 `COLUMNS` 中
- `chunk_size` 和 `chunks` 必须都是正整数
- 当前不会自动对 postgres 做同样改写

### 5.4 压缩配置

可选字段：

```properties
job.audit.COMPRESS.ENABLED=true
job.audit.COMPRESS.MODE=gz
job.audit.COMPRESS.OVERWRITE=true
job.audit.COMPRESS.REMOVE_ORIGINAL=false
```

字段解释：

- `COMPRESS.ENABLED`
  是否启用压缩，`true` 或 `false`
- `COMPRESS.MODE`
  压缩格式，当前支持 `gz`、`tar`、`tar.gz`、`tgz`
- `COMPRESS.OVERWRITE`
  如果目标压缩文件已存在，是否覆盖
- `COMPRESS.REMOVE_ORIGINAL`
  压缩成功后是否删除原始导出文件

### 5.5 传输配置

可选字段：

```properties
job.finance.TRANSFER.ENABLED=true
job.finance.TRANSFER.DIR=${ENV_TRANSFER_ROOT}
job.finance.TRANSFER.MODE=copy
job.finance.TRANSFER.OVERWRITE=true
job.finance.TRANSFER.RENAME=00-${job.finance.TABLE_NAME}-${EXPORT_DATE}.${job.finance.COMPRESS.MODE}
```

字段解释：

- `TRANSFER.ENABLED`
  是否启用传输
- `TRANSFER.DIR`
  目标目录
- `TRANSFER.MODE`
  `copy` 或 `move`
- `TRANSFER.OVERWRITE`
  目标文件已存在时是否覆盖
- `TRANSFER.RENAME`
  目标文件名模板

文件名模板支持：

- `${JOB_NAME}`
- `${EXPORT_DATE}`
- `${BASENAME}`

例如：

```properties
job.finance.TRANSFER.RENAME=00-${job.finance.TABLE_NAME}-${EXPORT_DATE}.${job.finance.COMPRESS.MODE}
```

如果 `TABLE_NAME=finance_report` 且 `COMPRESS.MODE=gz`，则目标名可能变成：

```text
00-finance_report-2026-03-17.gz
```

## 6. 输出内容怎么理解

### 6.1 Runtime 区块

示例：

```text
== Runtime ==
EXPORT_DATE=2026-03-17
TODAY=2026-03-17
YESTERDAY=2026-03-16
EXPORT_MONTH=2026-03
MONTH_START=2026-03-01
MONTH_END=2026-03-31
```

含义：

- 这是本次运行实际使用的日期变量

### 6.2 Job 区块

示例：

```text
== Job: users ==
DB_PROFILE=primary
DB_TYPE=mysql
DB_HOST=localhost
DB_PORT=3306
TABLE=users
COLUMNS=id,name,email
EXPORT_FILE=./tmp/demo_exports/users_2026-03-17.csv
FIELD_SEPARATOR=\t
LINE_TERMINATOR=\n
SQL=SELECT id,name,email FROM users WHERE status = 'active'
```

含义：

- 显示这个 job 最终解析后的配置和 SQL

### 6.3 成功日志

示例：

```text
JOB_OK name=users stage=complete
```

含义：

- 该 job 已完成当前命令要求的阶段

### 6.4 失败日志

示例：

```text
JOB_FAIL name=invalid_missing_profile stage=plan reason=plan build failed
```

含义：

- 该 job 在 `plan` 阶段失败
- 但流程仍会继续处理其他 job

### 6.5 Summary

示例：

```text
SUMMARY total=7 ok=5 failed=2
FAILED_JOBS=invalid_missing_profile invalid_unknown_profile
```

含义：

- 总共处理了 7 个 job
- 其中 5 个成功，2 个失败

## 7. 退出码规则

项目当前约定：

- 只有命令行参数错误时返回 `1`
- 其他运行期错误一律记录日志，进程返回 `0`

### 7.1 会返回 `1` 的情况

例如：

- 没传 `--db-config`
- 没传 `--jobs-config`
- `--date` 不是 `YYYY-MM-DD`

### 7.2 仍然返回 `0` 的情况

例如：

- 某个 job 缺失 `DB_PROFILE`
- 某个 selector 不存在
- 某个 job 对应 profile 不完整
- 导出时数据库命令失败
- 压缩或传输失败

原因：

- 当前设计要求尽量跑完整个批次
- 失败通过日志和 summary 观察

## 8. 常见使用示例

### 8.1 检查所有 job 是否能解析

```bash
bash script/bin/exportctl.sh validate \
  --db-config script/etc/demo/db.properties \
  --jobs-config script/etc/demo/jobs.properties \
  --env-config script/etc/demo/env.properties \
  --date 2026-03-17
```

适用场景：

- 改完配置后先检查哪些 job 会失败
- 只想确认配置能否通过，不关心 SQL 明细

### 8.2 只看某几个 job 的 SQL

```bash
bash script/bin/exportctl.sh plan \
  --db-config script/etc/demo/db.properties \
  --jobs-config script/etc/demo/jobs.properties \
  --env-config script/etc/demo/env.properties \
  --date 2026-03-17 \
  users finance
```

适用场景：

- 核对最终 SQL
- 核对最终输出文件路径
- 核对 split 列是否已被正确展开为 `SUBSTRING(...)`

### 8.3 混合 selector

```bash
bash script/bin/exportctl.sh plan \
  --db-config script/etc/demo/db.properties \
  --jobs-config script/etc/demo/jobs.properties \
  --env-config script/etc/demo/env.properties \
  --date 2026-03-17 \
  users invalid_unknown_profile missing_job
```

你会看到：

- `users` 正常输出
- `invalid_unknown_profile` 输出 `JOB_FAIL`
- `missing_job` 输出 unknown selector 错误

### 8.4 真正执行导出

```bash
bash script/bin/exportctl.sh run \
  --db-config script/etc/demo/db.properties \
  --jobs-config script/etc/demo/jobs.properties \
  --env-config script/etc/demo/env.properties \
  --date 2026-03-17 \
  users daily_orders audit finance
```

适用场景：

- 真正导出并生成文件
- 需要结合本机 `mysql` 或 `psql` 客户端使用

## 9. 推荐的手工检查方式

如果你想自己完整检查一遍，建议按下面顺序：

1. 先看 demo 配置

```bash
sed -n '1,200p' script/etc/demo/db.properties
sed -n '1,240p' script/etc/demo/jobs.properties
sed -n '1,120p' script/etc/demo/env.properties
```

2. 跑 demo 脚本

```bash
bash script/bin/demo_exportctl.sh
```

3. 再手动跑单个命令

```bash
bash script/bin/exportctl.sh plan \
  --db-config script/etc/demo/db.properties \
  --jobs-config script/etc/demo/jobs.properties \
  --env-config script/etc/demo/env.properties \
  --date 2026-03-17 \
  users
```

4. 如果要接真实数据库，再替换 `db.properties` 和相关密码文件配置

## 10. 当前设计限制

- `WHERE` 是 RAW SQL，程序不做语义校验
- 只支持 `mysql` 和 `postgres`
- 只有参数错误会返回 `1`
- 运行期失败必须看日志和 `SUMMARY`

如果你后面还要，我可以继续把这份手册补成：

- 配置字段对照表版本
- 调度系统接入指南版本
- 问题排查 FAQ 版本
