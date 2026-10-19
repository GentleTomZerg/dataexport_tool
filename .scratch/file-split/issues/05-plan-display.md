# 05 — plan / validate 展示 FILE_SPLIT

Status: ready-for-agent
Type: task
Blocked by: 01

Spec: `.scratch/file-split/spec.md`

## 目标

`plan` 输出文件拆分配置，便于排查。

## 改动

- `script/bin/exportctl.sh` `print_plan`：
  - 打印 `FILE_SPLIT=disabled`，或 `FILE_SPLIT=size=2G index_width=2 export_template=...`。
- `validate` 沿用 01 的校验路径，不额外打印 SQL。

## 验收

- 启用与未启用各有一条断言；`validate` 不打印 `SQL=`（保持现状）。

## 测试

`script/test/exportctl_test.sh`。
