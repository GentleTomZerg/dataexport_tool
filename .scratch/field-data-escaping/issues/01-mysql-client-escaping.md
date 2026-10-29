# 01 — mysql 导出改为客户端转义（去掉 --raw）

Status: resolved
Type: task
Blocked by: -

Spec: `.scratch/field-data-escaping/spec.md`

## 目标

让数据里的 tab / LF 不再冒充字段分隔符或行终止符。

## 改动

- `script/lib/exportctl/run/db.sh`
  - mysql 调用去掉 `--raw`：`mysql --batch --skip-column-names`，客户端即按 `\0` / `\t` / `\n` / `\\` 转义。
  - 新增函数头注释，写明契约、`--raw` 不得加回的原因，以及 CR 的已知限制。
  - `_sanitize_fields` 逻辑不变（仍只做 `NULL` → 空、`|!` → 替换）。
- 不新增任何配置项：所有 job 立即生效。
- CR 不转义：`mysql --batch` 无论带不带 `--raw` 都原样写出 CR（客户端 `tee_write` 只处理 `\t` / `\n` / `\\`），而 CR 不破坏结构，故透传，作为已知限制记录。

## 验收

- 数据里的 tab 在产物中是 `\` `t` 两个字节，不再变成 `|!`，字段数不变。
- 数据里的 LF 在产物中是 `\` `n`，不再把一行切成两行。
- 数据里的真实 CR 原样透传（已知限制），且不改变行数与字段数。
- 已经被客户端转义过的 `\t` / `\n` / `\0` / `\\` 不被二次转义。
- 既有行为不变：`|!` → `FIELD_SEPARATOR_DATA_REPLACEMENT`、`NULL` → 空、末尾空字段保留。

## 测试

- 新增 `script/test/escaping_test.sh`：变换层的完整矩阵（tab / LF / NUL / 反斜杠 / 字面 `\t` / `|!` / `NULL` / `\N` / 末尾空字段 / 全危险字符同字段 / CR 透传 / 行数 / 字段数 / 空输入），并已加入 `run_all.sh`。
- `script/test/exportctl_test.sh`：fake `mysql` 改为按 `--batch` / `--raw` 两种模式建模，逐 job 端到端断言转义、字段数与行数。
- 反证：把 `--raw` 加回去，端到端测试立刻失败（已人工验证）。

## Comments

- 决策：无开关、所有 job 同批生效；消费方负责反转义（ADR-0002）。
- 决策：postgres 分支不动，见工单 `04`。
