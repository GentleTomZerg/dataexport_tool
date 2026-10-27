# 04 — NULL 与字面量 'NULL' 的歧义

Status: needs-info
Type: task
Blocked by: 01

Spec: `.scratch/field-data-escaping/spec.md`

## 问题

`_sanitize_fields` 把字段文本 `NULL` 置为空。mysql batch 模式对"真 NULL"与"字符串 'NULL'"输出完全相同的字节，所以两者无法区分：一个非空文本列里写了 `NULL`，导出后变成空。

postgres 分支不受影响也不用处理：`\copy ... FORMAT text` 输出 `\N`，当前的 `NULL` 判断根本匹配不到——也就是说 postgres 的真 NULL **今天没被置空**，两个分支对 NULL 的行为不一致。

## 待定

- 是否区分：mysql 侧没有原生 NULL 标记，只有 `--xml` / `--table`、或 SQL 侧 `IFNULL`/`COALESCE` 加哨兵这些更重的做法。
- 或者接受歧义，把"文本 `NULL` 会被置空"写成手册里的已知限制。
- postgres 侧的 `\N` 应该置空、还是原样保留。

## 备注

本工单与转义正交：转义解决的是"数据字符冒充结构"，这里是"标记值与数据值不可区分"。工单 `02` 已把当前行为写进手册。
