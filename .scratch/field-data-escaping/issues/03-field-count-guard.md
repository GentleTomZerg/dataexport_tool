# 03 — 字段数护栏（期望列数从哪来）

Status: needs-info
Type: task
Blocked by: 01

Spec: `.scratch/field-data-escaping/spec.md`

## 目标

把"字段数悄悄变了"从静默数据损坏变成一条可见的日志：转义一旦回退（例如 `--raw` 被加回来、或某客户端行为变化），当天就能发现。

## 已定的部分

- 计量点固定在 `_sanitize_fields` 内部：那里看到的是客户端原始 tab 边界，早于转义与分隔符替换；`NR` 即产物中的行号。
- 输出**只走 stderr**（stdout 是导出文件，多一个 printf 就污染数据）。
- 非致命，遵守项目既有约定：运行时异常记录日志、仍 `exit 0`。
- 每条不匹配打印 `line=<NR> fields=<NF> expected=<N>`，前 20 条后汇总总数，避免 2G 文件刷爆日志。
- 日志前缀不能与既有 `ERROR:` 冲突（`ERROR:` 在本项目里等于"job 失败"，grep 告警依赖这一点）。

## 待定（因此本工单停在 needs-info）

**期望列数从哪来。** 已确认的选项：

- **A. 用户配置**（`job.<name>.COLUMN_COUNT`）：实现最省。风险是与 `COLUMNS` / `SPLIT` 漂移——`SPLIT.blog=10000,3` 时真实列数是 `len(COLUMNS) - 1 + 3`，要人肉算；算错则 100% 行报警，报警很快被忽略。
- **B. 推导**：`render_select_columns` 内部的 `rendered` 数组长度就是准确答案（展开 `SPLIT` 之后），需要把它带进 `plan`（约 3 行）。不能靠数渲染 SQL 里的逗号——`SUBSTRING(col, 1, 10000)` 自带逗号。
- **C. 推导 + 配置覆盖**：`B` 作为默认，`A` 作为显式覆盖。

当前倾向 B/A 混合（C），但用户要求推迟决定。

## 测试（依赖上面的决定）

- 某行多出一个裸 tab 时：stderr 出现护栏日志、job 仍成功、产物仍写出。
- `plan` 输出中出现列数字段。
