# 06 — 文档与示例配置

Status: ready-for-agent
Type: task
Blocked by: 01

Spec: `.scratch/file-split/spec.md`

## 目标

把文件拆分写进用户手册与示例配置。

## 改动

- `script/USER_MANUAL_ZH.md`：新增 `FILE_SPLIT.*` 章节；说明 `${PART}`、gz 计量、两遍落地、前置约束（`COMPRESS.MODE=gz`）、陈旧清理范围、边界语义。
- `script/etc/demo/jobs.properties`：加一个文件拆分示例。
- 说明名字里的 `1G/2G` 是增量/全量业务标记，与大小无关。

## 验收

- 手册字段表与 spec 一致。
- 示例可直接被 `validate` 通过（依赖 01 的校验）。
