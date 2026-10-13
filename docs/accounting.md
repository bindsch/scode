# Usage accounting

Set `SCODE_ACCOUNT_FILE` to enable one JSON line at exit for invocations
that pass argument parsing. Failed setup/launches and dry-runs can record.
Help, version, and audit do not. The optional `SCODE_ACCOUNT_ID` correlates runs.

```sh
SCODE_ACCOUNT_FILE="$PWD/usage.jsonl" SCODE_ACCOUNT_ID=build-17 scode --dry-run -- true
```

For real runs, choose a sink outside the sandbox's writable area. Removing the
variables from the child environment hides their values; it does not protect
a child-writable sink from forgery.

## Schema and units

| Field | Type | Meaning |
|---|---|---|
| `ts` | string | UTC exit timestamp; on date failure, epoch text or `unknown` |
| `event` | string | Always `scode_exit` |
| `platform` | string | `darwin`, `linux`, or `unknown` before successful detection |
| `exit_code` | integer | Wrapper result; see [exit statuses](cli.md#exit-statuses) |
| `duration_s` | integer or null | End minus start wall-clock seconds; null when timestamps cannot be parsed |
| `scratch_kib` | integer or null | `du -sk` allocated storage units of 1,024 bytes, measured before teardown |
| `scratch_path` | string or null | macOS private scratch path, omitted for unsupported characters or record size |
| `account_id` | string or null | Caller token if valid |
| `reason` | string | Measurement result from the table below |

IDs allow letters, digits, and `. _ : -`, up to 128 characters.
Invalid or longer IDs become null; they are not truncated.
Duration is wall-clock time, not CPU time or a monotonic measurement.

| `reason` | Meaning |
|---|---|
| `""` | macOS scratch measurement succeeded |
| `no_scratch` | No scratch to measure, including dry-run and Linux engine-not-found |
| `tmpfs_unmeasurable` | Linux launch was attempted; parent cannot measure the namespace's private tmpfs |
| `du_failed` | macOS `du` failed; partial output is rejected and size is null |

The macOS measure covers only scode's private per-run scratch directory.
It excludes other temporary paths, separate logging/preload directories,
project output, and peak usage. macOS engine-not-found can still record an
allocated empty scratch directory. Linux's label records a launch attempt,
not proof that a namespace formed.

Representative records (timestamps, paths, and sizes are illustrative):

```json
{"ts":"2026-10-13T08:00:00Z","event":"scode_exit","platform":"darwin","exit_code":0,"duration_s":2,"scratch_kib":16,"scratch_path":"/private/tmp/scode.501.example","account_id":"build-17","reason":""}
{"ts":"2026-10-13T08:01:00Z","event":"scode_exit","platform":"linux","exit_code":0,"duration_s":0,"scratch_kib":null,"scratch_path":null,"account_id":null,"reason":"no_scratch"}
{"ts":"2026-10-13T08:02:00Z","event":"scode_exit","platform":"linux","exit_code":1,"duration_s":1,"scratch_kib":null,"scratch_path":null,"account_id":null,"reason":"tmpfs_unmeasurable"}
```

## Sink validation and concurrency

Relative paths use the invoking directory; the parent must already exist.
The sink must be a regular file, not a symlink, FIFO, or device.
scode opens an append descriptor when accounting is armed and creates the
file then if needed. Parent-directory fingerprints and sink identity are
checked again before accepting the record. Replaced paths drop the record;
the existing descriptor remains the write destination.

Each JSON payload is bounded at 800 bytes, plus one newline byte.
Oversized paths are nulled first; a still-oversized record is dropped.
The bounded single append avoids interleaving among normal local-file
appenders on the tested platforms. This does not promise transactional storage
on arbitrary network filesystems.

Append failure warns and attempts a newline to terminate a partial record.
Accounting failures do not replace the command's result or suppress teardown.
An abrupt kill or host failure can prevent any record. A surviving child,
including the [PID-directed QUIT case](platforms.md#signals), means an exit
record need not mark the end of all descendant work.
