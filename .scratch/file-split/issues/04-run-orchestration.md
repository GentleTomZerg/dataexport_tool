# 04 — run 编排：草稿生命周期、陈旧清理、逐 part 传输

Status: ready-for-agent
Type: task
Blocked by: 01, 02, 03

Spec: `.scratch/file-split/spec.md`

## 目标

把切片接进 `run` 流程，并处理草稿与陈旧 part。

## 改动

- `script/bin/exportctl.sh` `execute_run_mode`：
  - 启用 `FILE_SPLIT` 时，Pass 1 把现有导出管道写入草稿 `dirname(EXPORT_FILE)/.file_split.<job>.<pid>/rows.csv`（草稿是内部产物，不受 `COMPRESS.REMOVE_ORIGINAL` 管辖）。
  - `trap ... EXIT` 删除草稿目录（成功与失败都删）。
  - 调 `split_and_compress_parts` 产出 part。
  - 逐 part 走该 job 的 `TRANSFER.*`，`RENAME` 的 `${PART}` 逐个渲染。
  - **陈旧清理**：本次产出 N 份后，在导出目录（temp）内按渲染后的 part 名前缀删除序号 ≥ N 的旧文件；**不碰 transfer 目录**（下游自动消费）。
  - 统计与日志：逐 part 打印 + 汇总；`lines` 与拆前一致；区分 `bytes_csv` 与 `bytes_gz`；`Final artifact ready` 每 part 一行。
- `script/lib/exportctl/run/artifact.sh`：`run_artifact_pipeline` 支持多 part（或在编排层循环调用）。

## 验收

- 未启用时 `run` 输出与现状逐字节一致（现有 `exportctl_test.sh` 全绿）。
- 启用时：草稿在成功/失败后都不存在；陈旧 part 被清掉；每 part 都被传输。

## 测试

扩展 `script/test/exportctl_test.sh`。
