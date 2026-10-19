# 07 — 端到端集成测试

Status: ready-for-agent
Type: task
Blocked by: 04

Spec: `.scratch/file-split/spec.md`

## 目标

用假 `mysql` 端到端验证多 part 场景。

## 改动

- `script/test/exportctl_test.sh`：
  - 假 `mysql` 输出远大于小 `MAX_SIZE` 的数据，断言拆出多份 part、命名/序号正确、每个 `.gz` ≤ 上限。
  - 断言 `lines` 与不拆分时相同。
  - 断言上一轮多出的 part 被清理。
  - 断言 transfer 目标目录出现对应数量的 part。
  - 覆盖空结果 → 1 个空 `00`。

## 验收

- `bash script/test/run_all.sh` 全绿。
