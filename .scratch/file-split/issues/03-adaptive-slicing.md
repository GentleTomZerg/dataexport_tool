# 03 — 自适应切片与逐片 gzip

Status: ready-for-agent
Type: task
Blocked by: 01

Spec: `.scratch/file-split/spec.md`

## 目标

给定一份未压缩 CSV 与 `MAX_SIZE`，在行边界上切成若干 part，每片单独 gzip，且每片 gz ≤ `MAX_SIZE`。

## 改动

- 新增 `script/lib/exportctl/run/split.sh`，核心函数例如 `split_and_compress_parts <csv_path> <plan_name>`：
  - 初始未压缩预算 `budget = MAX_SIZE × 3`。
  - 按行边界取出累计未压缩字节 ≤ `budget` 的切片，gzip 到渲染后的 part 名。
  - 每片后用实测压缩比校准下一片：`budget = MAX_SIZE × (chunk_bytes / gz_bytes) × 0.95`。
  - 某片 gz > `MAX_SIZE` 时再切一次（罕见）。
  - **绝不从行中间切**；每片至少一行，故单行超限时允许该 part 超过 `MAX_SIZE`。
  - 空 CSV 产出 1 个空的 `00` part。
  - 返回每片 `(index, lines, bytes_csv, bytes_gz)` 供统计。

## 验收

- 用小尺寸合成 CSV 覆盖：恰好一份、多份、跨行、单行超限、空输入。
- 每个产出的 `.gz` 均可 `gzip -cd` 且内容按切片顺序拼接后与源 CSV 完全一致（行不丢不重）。

## 测试

新增单测直接调用该函数，不依赖数据库。
