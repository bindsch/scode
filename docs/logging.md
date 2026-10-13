# Stderr capture and audit

```sh
scode --log session-001.log --strict codex
scode audit session-001.log
scode audit --watch session-001.log
```

`--log` captures command stderr through `tee`, mirrors it to scode's stderr,
and writes policy metadata. It is not a comprehensive kernel-denial collector.
Suppressed application errors, messages written elsewhere, and kernel-only
events can be absent. Stdout is not captured.

## Destination and sensitive contents

Relative paths resolve against the invoking directory, not `--cwd`.
Missing parent directories are created. An existing destination is replaced
with a new mode-0600 regular file; this is not append mode. A destination
symlink is replaced itself, not written through. A directory destination is
rejected. Parent directories retain their own permissions.

The writer keeps a descriptor to the installed inode, so a later destination
rename does not redirect its writes. This does not stop a child from changing
a log stored in a writable project. Use a unique session path outside the
sandbox's writable area.

Headers contain exact argv and policy paths. The body contains all stderr,
which can include prompts, tokens in arguments, application diagnostics, and
other sensitive data. There is no general secret redaction. Terminal escaping
prevents control-sequence rendering in selected diagnostics; it does not make
the log safe to share.

## Header schema

The first line begins `#json:`, followed by one JSON object:

| Field | Type | Meaning |
|---|---|---|
| `version` | integer | Schema version, currently 1 |
| `session` | string | Local timestamp, `YYYY-MM-DDTHH:MM:SS±HHMM` |
| `command` | string | Flattened requested command; argument boundaries are ambiguous |
| `argv` | array of strings | Exact requested argument boundaries before execution rewriting |
| `cwd` | string | Canonical selected project |
| `blocked` | array of objects | Each has string `source` and `path` |
| `allowed` | array of strings | Explicit grants plus automatic strict harness state |

Block sources are `default`, `platform`, `config`, `project`, `cli`,
and `defense`. The header is policy metadata, not a complete authority model:
system paths, project access, and runtime exceptions also matter.

```json
{"version":1,"session":"2026-10-13T10:00:00+0200","command":"tool two words","argv":["tool","two words"],"cwd":"/work/project","blocked":[{"source":"cli","path":"/work/project/private"}],"allowed":["/work/reference"]}
```

Legacy `# command:`, `# cwd:`, `# blocked:`, and `# allowed:` lines follow,
then profile/engine comments and `#---`. The built-in audit parser reads those
legacy lines, not the JSON object. Logs without blocked metadata fall back to
built-in defaults. External tools should consume `argv` instead of splitting
`command`.

## Batch audit and watch

Audit heuristically recognizes macOS `deny(file-...)`, Unix
`Permission denied` / `Operation not permitted`, Node EACCES, and Python
OSError path formats. These messages can also describe ordinary filesystem
permissions; parsing is not proof that the sandbox caused an error.

Batch output groups paths by blocked parent. Default/platform groups can get
`--allow` suggestions; custom policy groups do not. This grouping is not
least-authority analysis. One credential-file denial can suggest reopening an
entire parent directory. Review every suggested subtree before granting it.

Watch starts at the end of the existing file, ignores old entries, and
deduplicates new paths for the lifetime of the watcher. It prints new denials
without batch categories or allow suggestions. Restarting resets deduplication.

## Completion and failure

After reaping the engine, the live writer sends
`scode-log-complete run <pid>-<token>` through the pipe and waits a bounded
time for it to reach the file. The token normally comes from OS randomness,
with a weaker shell-random fallback. The marker also appears on mirrored stderr.
The live check establishes that the writer reached that marker; it does not
authenticate the saved artifact.

`scode audit` does not validate the marker token or require a complete log.
A final marker-looking line is not independent proof of completion.
A child that can modify the log can forge its contents. Output from a
daemonized grandchild after engine reap may be lost.

An incomplete or failed requested log makes a successful run nonzero.
If the marker arrived but the writer exceeds its drain grace, scode can stop
it and warn that the stderr mirror may lack a tail even though the file reached
the marker. See [exit statuses](cli.md#exit-statuses) and
[signals](platforms.md#signals).
