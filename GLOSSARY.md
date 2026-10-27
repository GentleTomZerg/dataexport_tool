# Data Export

A tool that copies rows from a database table into delimited files, then optionally compresses and transfers those files.

## Language

**Job**:
A named, configured export: one table's rows selected, transformed, and written out.
_Avoid_: task, export (as a noun)

**Export file**:
The file a job's rows are first written to, before compression or transfer.
_Avoid_: output, dump

**Artifact**:
A file a job has finished producing and hands to the next stage (compression, transfer).
_Avoid_: output, result

**File split**:
Dividing a job's rows across several part files instead of one.
_Avoid_: sharding, chunking, segmentation

**Part**:
One file in a file-split job's output; every row belongs to exactly one part.
_Avoid_: chunk, shard, segment, slice

**Column split**:
Widening a row by replacing one column with several substring columns.
_Avoid_: file split

**Column chunk**:
One substring column produced by a column split.
_Avoid_: part, piece

**Field separator**:
The character sequence that separates one field from the next in an export file; configured per job (`FIELD_SEPARATOR`), `\t` by default.
_Avoid_: delimiter, field terminator, column separator

**Line terminator**:
The character sequence that ends a record in an export file; configured per job (`LINE_TERMINATOR`), `\n` by default.
_Avoid_: newline, row delimiter, EOL

**Data escaping**:
The rule that a field's own data never contains a raw tab or LF: those bytes appear as the two-character sequences `\t` and `\n`, a backslash appears as `\\`, and NUL appears as `\0`. It keeps one row on one line with a fixed field count, whatever the data. Consumers must unescape before use.
_Avoid_: quoting, sanitizing, encoding

**Runtime variables**:
Date-derived values (e.g. `EXPORT_DATE`, `YESTERDAY`) available when a job's configuration is expanded.
_Avoid_: parameters, args
