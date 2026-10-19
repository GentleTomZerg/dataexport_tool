# 02 — `${PART}` 渲染与序号溢出

Status: ready-for-agent
Type: task
Blocked by: 01

Spec: `.scratch/file-split/spec.md`

## 目标

让 `EXPORT_FILE` 与 `TRANSFER.RENAME` 中的 `${PART}` 渲染成按 `INDEX_WIDTH` 零填充的序号。

## 改动

- `script/lib/exportctl/run/artifact.sh`
  - 扩展 `_render_artifact_name`，增加 part 序号参数，渲染 `${PART}`（宽度 = `INDEX_WIDTH`，从 `00` 起）。
  - `EXPORT_FILE` 目前是原样使用、不经渲染；新增对 export 模板的渲染（供切分阶段按 part 命名）。
  - 序号需要 ≥ `10^INDEX_WIDTH` 时报错，提示调大 `INDEX_WIDTH`（不做动态加宽）。

## 验收

- `INDEX_WIDTH=2` 时渲染出 `00`、`01`、…、`99`；`100` 直接报错。
- `EXPORT_FILE` 与 `TRANSFER.RENAME` 使用同一套占位符语义。

## 测试

`script/test/` 下新增或复用，断言渲染结果与溢出报错。
