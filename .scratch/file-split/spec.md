# 文件拆分（File Split）Spec

Status: confirmed

## 背景

单个 job 的导出结果可能很大（gz 后可达数 G），下游 EDP 希望拿到的是**按大小切好、带序号前缀的一批文件**，而不是一个超大文件。命名形如：

```
00-LENS-${TABLE_NAME}-${EXPORT_DATE}-2G.gz
01-LENS-${TABLE_NAME}-${EXPORT_DATE}-2G.gz
02-LENS-${TABLE_NAME}-${EXPORT_DATE}-2G.gz
```

其中 `00/01/02` 是**自增序号**；名字里的 `1G/2G` 是**增量/全量的业务标记，与文件大小无关**，由配置人自己书写，工具不解析、不替换。

## 术语（见 `GLOSSARY.md`）

- **file split**：把一个 job 的行集合分散到多个 part 文件。
- **part**：file split 后的其中一个文件；每一行恰好属于一个 part。
- 与既有的 **column split / column chunk**（`SPLIT.<column>`，纵向加宽列）无关且正交。

## 配置

新增 job 级配置（默认关闭）：

| 配置键 | 默认 | 说明 |
|---|---|---|
| `job.<name>.FILE_SPLIT.ENABLED` | `false` | 是否启用文件拆分 |
| `job.<name>.FILE_SPLIT.MAX_SIZE` | 无（启用时必填） | 每个 part 的大小上限；支持 `K/M/G` 后缀，1024 进制；也接受纯字节数 |
| `job.<name>.FILE_SPLIT.INDEX_WIDTH` | `2` | 序号位数，零填充，从 `00` 起自增 |

模板变量：

- `${PART}`：渲染为按 `INDEX_WIDTH` 零填充的序号（`00`、`01`、…），在 `EXPORT_FILE` 与 `TRANSFER.RENAME` 中均可用。

示例：

```properties
job.users.FILE_SPLIT.ENABLED=true
job.users.FILE_SPLIT.MAX_SIZE=2G
job.users.EXPORT_FILE=${ENV_GTP_TEMP_PATH}/${PART}-LENS-${job.users.TABLE_NAME}-${EXPORT_DATE}-2G
job.users.TRANSFER.RENAME=${PART}-LENS-${job.users.TABLE_NAME}-${EXPORT_DATE}-2G.${job.users.COMPRESS.MODE}
```

## 约束与校验

启用 `FILE_SPLIT` 时，以下不满足**一律报错**（与现有 job 校验同一路径，`validate`/`plan`/`run` 都生效）：

1. `EXPORT_FILE` 必须包含 `${PART}`。
2. 必须 `COMPRESS.ENABLED=true`，且 `COMPRESS.MODE=gz`（`tar`/`tgz` 是归档容器，无法按字节切分，也无法按 gz 计量）。
3. 若 `TRANSFER.ENABLED=true`，`TRANSFER.RENAME` 必须包含 `${PART}`（否则各 part 会互相覆盖）。
4. `MAX_SIZE` 必须可解析且 > 0；`INDEX_WIDTH` 必须是 > 0 的整数。
5. 允许与 `SPLIT.<column>` 列拆分同时启用。

## 计量口径

- **上限按压缩后的 gz 字节数衡量**：每个 part 的 `.gz` 应 ≤ `MAX_SIZE`。
- 由于 gz 是压缩产物、无法在流式导出时预知大小，采用**两遍落地**方案：
  - Pass 1：沿用现有导出管道，把整份未压缩 CSV 落到临时草稿文件。
  - Pass 2：读草稿、按"实测压缩比"自适应切片，每个切片单独 gzip。

## 执行流程（`FILE_SPLIT.ENABLED=true` 时）

1. **Pass 1（导出）**：`mysql|psql → sanitize → separators` 写入草稿 CSV。
   - 草稿位置：`EXPORT_FILE` 所在目录下的专用临时目录，例如 `dirname(EXPORT_FILE)/.file_split.<job>.<pid>/rows.csv`。
   - 草稿是工具内部产物，**不受 `COMPRESS.REMOVE_ORIGINAL` 管辖**；成功或失败都在退出时删除（`trap ... EXIT`）。
   - 同时统计未压缩字节数与行数。
2. **Pass 2（自适应切片并逐 part 压缩）**：
   - 初始未压缩预算 `budget = MAX_SIZE × 3`（压缩比猜测）。
   - 按行边界取出未压缩字节累计 ≤ `budget` 的切片，gzip 到 `render(EXPORT_FILE, ${PART})`。
   - 用实测压缩比校准下一片：`budget = MAX_SIZE × (chunk_bytes / gz_bytes) × 0.95`。
   - 若某片 gz > `MAX_SIZE`，再切一次该片（罕见）。
   - **绝不从行中间切**；每片至少包含一行，因此单行超限时该 part 允许超过 `MAX_SIZE`。
3. **清理陈旧 part**：本次产出 N 份后，在**导出目录（temp）**内，按该 job 渲染后的 part 名前缀，删除序号 ≥ N 的旧文件。
   - **不清理 transfer 目录**：其内容由下游自动消费并删除。
4. **传输**：每个 part 各自走该 job 的 `TRANSFER.*` 配置，`RENAME` 中的 `${PART}` 逐个渲染。
5. **清理草稿**：退出时删除临时目录（成功与失败都删）。

## 统计与日志

- 行数统计与不拆分时**完全一致**（切点只在行之间，不增不减）。
- `bytes` 区分两个口径：`bytes_csv`（未压缩，与今天同义）与 `bytes_gz`（每个 part 的 gz 之和）。
- 逐 part 打印，并汇总；`Final artifact ready` 改为 N 行（每 part 一行）。
- `plan` 增加打印：`FILE_SPLIT=disabled` 或 `FILE_SPLIT=size=2G index_width=2 export_template=...`。

## 边界语义

- **空结果**：产出 1 个空的 `00` part（保持"成功的 job 至少有一个 `00`"的不变量）。
- **单行超限**：该 part 允许超过 `MAX_SIZE`。
- **超过位宽**：产出份数需要 ≥ `10^INDEX_WIDTH` 时报错中止，提示调大 `INDEX_WIDTH`（不做动态加宽，避免同批文件名排序不一致）。
- **不支持**：`FILE_SPLIT` 与 `tar`/`tgz`、与未启用压缩的组合。

## 非目标

- 不改动既有的 `COMPRESS.*` / `TRANSFER.*` 语义（只是从"单文件"改为"逐 part"）。
- 不引入新的运行时依赖（保持 bash + awk + gzip）。
- 不做流式（方案 A）；不做"按未压缩字节计量"（方案 C）。原因见 ADR。

## 相关决策

- ADR-0001：`docs/adr/0001-file-split-measured-on-gz.md`（按 gz 计量 → 两遍落地 B）。

## 工单

见 `.scratch/file-split/issues/`。
