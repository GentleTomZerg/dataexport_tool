# 02 — 文档：术语、手册、ADR

Status: resolved
Type: task
Blocked by: 01

Spec: `.scratch/field-data-escaping/spec.md`

## 目标

把转义契约写进术语表与用户手册，别让下一个人看到字段里的 `\t` 以为是没修完的 bug。

## 改动

- `GLOSSARY.md`：新增 **field separator**、**line terminator**、**data escaping** 三个术语（此前只有 `|!` 配置名，没有术语）。
- `script/USER_MANUAL_ZH.md`：§6.2 重写 `FIELD_SEPARATOR` / `FIELD_SEPARATOR_DATA_REPLACEMENT` 说明，新增转义表与消费方反转义义务；§6.5 新增"字段数据转义"小节。
- `docs/adr/0002-field-data-is-escaped.md`：记录"在客户端转义而非替换"的决策与代价。

## 验收

- 手册与 spec 的转义表逐字一致。
- 手册明确写出 `FIELD_SEPARATOR_DATA_REPLACEMENT` 作用在**已转义**的字段文本上。
- 手册明确写出消费方必须反转义（`\\` 先行），否则含反斜杠的数据会读错。

## Comments

- 术语缺口是在设计过程中发现的：对话里一直说 "field terminator"，代码与配置里叫 `FIELD_SEPARATOR`。
