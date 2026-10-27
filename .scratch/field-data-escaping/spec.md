# 字段数据转义（Field Data Escaping）Spec

Status: confirmed

## 背景

表里的字段可能含有制表符、换行符、回车符等字符。今天这些字符会**冒充结构**：

- `mysql` 调用带 `--raw`，客户端不做任何转义，数据里的真实 `\t` / `\n` 会原样输出；
- `_sanitize_fields` 以真实 tab 分列，于是数据里的 tab 被当成列边界，行里凭空多出一列；
- `_apply_separators` 再把该边界渲染成 `FIELD_SEPARATOR`，即 `|!`。

结果：下游看到的行比配置的 `COLUMNS` 多，且没有任何报错。数据里的换行符更严重——一行被切成两行，`FILE_SPLIT` 的切点与 `lines=` 统计同时被污染。

## 术语（见 `GLOSSARY.md`）

- **field separator / line terminator**：结构字符，由配置决定，用于分隔字段与行。
- **data escaping**：字段数据内部的字节表示法；转义后数据里不存在裸的 tab / LF / CR。

## 契约

导出文件的字段数据**永不**包含裸的 `\t`（0x09）或 `\n`（0x0A）字节——它们是唯一会破坏结构的两类字节。这两个字节以**两个字符**的序列出现：

| 数据中的字符 | 导出文件中的字节 | 字节数 |
|---|---|---|
| tab (0x09) | `\` `t` | 2 |
| LF (0x0A) | `\` `n` | 2 |
| `\` (0x5C) | `\` `\` | 2 |
| NUL (0x00) | `\` `0` | 2 |

由此得到不变量：**一行 = 一条记录，且每条记录的字段数恒等于 `COLUMNS` 展开后的列数**，与数据内容无关。

CR（0x0D）**不在**契约内：`mysql --batch` 无论是否带 `--raw` 都把它原样写出（客户端源码 `tee_write` 只处理 `\t` / `\n` / `\\`，尽管 `MY_PRINT_CTRL` 的注释声称包含 CR）。CR 既不冒充字段分隔符也不冒充行终止符，因此原样透传；`postgres` 的 `COPY ... FORMAT text` 则输出 `\r`。两个分支在这一点上不一致，属于已知限制。

## 消费方义务

消费方必须**反转义**才能拿到原值，且顺序为 `\\` 先行，再 `\t` / `\n` / `\r`。仅仅"不再按 tab 切分"是不够的：含字面反斜杠的数据会变成 `\\`，反转义后才是正确的单个 `\`。

这是每个 job 的迁移项，不是无痛变更。

## 实现

1. `script/lib/exportctl/run/db.sh`：`mysql` 调用去掉 `--raw`，让客户端做它本来就会做的转义（NUL / tab / LF / 反斜杠）。
2. 无新增配置项、无开关：所有 job 同时生效。`_sanitize_fields` 保持原有职责（`NULL` → 空、`|!` → `FIELD_SEPARATOR_DATA_REPLACEMENT`），不再增加转义逻辑。

## 边界与已知限制

- **CR 不转义**：见上，mysql 客户端把它原样写出；postgres 输出 `\r`。两个分支在此不一致。
- **postgres 分支未改动**：`\copy ... FORMAT text` 本来就转义 tab / LF / CR / 反斜杠，已满足上述契约。该分支仍无自动化测试。
- **`NULL` 与字面量 `'NULL'` 不可区分**（mysql batch 模式只输出 `NULL`）：今天两者都被置空。postgres 输出 `\N`，不走这条分支。见工单 `04`。
- 仅以裸 tab 分列；若客户端仍吐出裸 tab（例如有人把 `--raw` 加回来），字段数会变化，需要工单 `03` 的护栏来发现。

## 非目标

- 不引入 `ESCAPE_DATA` 之类的逐 job 开关（决策记录见 ADR-0002）。
- 不改 `FIELD_SEPARATOR` / `LINE_TERMINATOR` 的语义。
- 不改 `SPLIT.<column>` / `FILE_SPLIT` / `COMPRESS.*` / `TRANSFER.*`。

## 相关决策

- ADR-0002：`docs/adr/0002-field-data-is-escaped.md`（转义优先于替换，也优先于 SQL 侧清洗）。

## 工单

见 `.scratch/field-data-escaping/issues/`。
