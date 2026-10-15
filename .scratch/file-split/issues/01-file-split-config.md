# 01 — FILE_SPLIT 配置解析与校验

Status: ready-for-agent
Type: task
Blocked by: -

Spec: `.scratch/file-split/spec.md`

## 目标

在 job 模型层支持文件拆分配置，并在启用时做完整前置校验。

## 改动

- `script/lib/exportctl/model/job.sh`
  - `extract_job_fields`：读取 `FILE_SPLIT.ENABLED` / `FILE_SPLIT.MAX_SIZE` / `FILE_SPLIT.INDEX_WIDTH`。
  - `apply_job_defaults`：`enabled=false`、`index_width=2`。
  - 新增大小解析函数（`K/M/G`，1024 进制，亦接受纯字节）。
  - 新增文件拆分校验，启用时下列任一不满足即报错：
    1. `EXPORT_FILE` 含 `${PART}`；
    2. `COMPRESS.ENABLED=true` 且 `COMPRESS.MODE=gz`；
    3. `TRANSFER.ENABLED=true` 时 `TRANSFER.RENAME` 含 `${PART}`；
    4. `MAX_SIZE` 可解析且 > 0，`INDEX_WIDTH` 为正整数。
  - 允许与 `SPLIT.<column>` 共存。
- `script/lib/exportctl/model/plan.sh`：把三个新字段带进 plan。

## 验收

- 未启用时行为与现状完全一致。
- 上述四类错误各有一条单测覆盖，报错信息含 job 名与字段名。

## 测试

`script/test/plan_test.sh`（或新增 `script/test/file_split_test.sh`）。
