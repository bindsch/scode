# Configuration

The default user file is `~/.config/scode/sandbox.yaml` under the account
home discovered independently of effective HOME. Selection priority is
`--config FILE`, then `SCODE_CONFIG`, then that default. Relative selectors
use the invoking directory. A missing default is optional; an explicitly
selected missing file is an error.

The project file is `.scode.yaml` at the selected project root.
See [policy precedence](policy.md#precedence) for how the sources combine.

## All accepted keys

| Key | Type / values | Built-in default | Project restriction | CLI equivalent |
|---|---|---|---|---|
| `blocked` | List of literal paths | Built-in path lists | May add blocks | `--block PATH` |
| `allowed` | List of literal paths | No explicit grants | Cannot authorize paths | `--allow PATH` |
| `net` | `on`, `off` | `on` | Only `off` tightens | `--no-net` |
| `fs_mode` | `rw`, `ro` | `rw` | Only `ro` tightens | `--ro` / `--rw` |
| `strict` | `true`, `false` | `false` | Only `true` tightens | `--strict` |
| `scrub_env` | `true`, `false` | `false` | Only `true` tightens | `--scrub-env` |
| `grok_defense` | `true`, `false` | `false` | Only `true` tightens | Config-only |

User config may set either scalar value. Project permissive values are ignored
and may warn. Project allows already authorized by the user/CLI are redundant;
others warn and are ignored. There is no config key for trust presets,
credential synchronization, logging, or `--keep-env`.

## Supported format

This is a line-oriented subset, not a general YAML parser. Use lowercase keys,
scalar values from the table, and `blocked:` / `allowed:` sections with
dash-prefixed path lines. Blank lines, full-line comments, CRLF, and a missing
final newline are accepted. Indentation does not establish a nested structure.
Scalars may follow lists; a scalar ends the current list section.
Duplicate scalars use the last value; repeated lists append.

Unquoted scalar values accept a whitespace-plus-`#` comment.
Unquoted list paths containing whitespace-plus-`#` are rejected, including
apparent inline comments. Quote the path instead. Single quotes support doubled
apostrophes. Double-quoted content retains backslash escapes literally; it is
not decoded as YAML or shell escapes. Quoted values may have trailing comments.

```yaml
strict: true # scalar comment
blocked:
  - '~/private # notes' # quoted list comment
  - "~/Documents/private"
allowed:
  - ./reference
```

Relative access paths use the project, not the config file's directory.
A leading `~/` expands to effective HOME. Variables, globs, and command
substitutions are literal path text; they are not evaluated.

These examples fail:

```yaml
strict: yes
allowed: [./cache]
blocked:
  - ./secret # unquoted list comment
```

Unknown keys, malformed quotes, empty list items, unsupported lines, anchors,
flow collections, multiline scalars, and document separators are unsupported.
Do not rely on YAML tags or indentation to give literal path text special
meaning. Errors identify the file and, for syntax errors, the line.

## File acceptance and remediation

Every parsed config is capped at 1 MiB (1,048,576 bytes). Split excessive policy
into the paths actually needed; includes are not supported.

A project config must be an owned regular file in the project root with one
hard link and no symbolic link. scode opens it once and checks the descriptor
against the path, owner, link count, and canonical location before parsing.
Replace a symlink or hard-linked file with a reviewed standalone copy.
Correct ownership only after reviewing the file. If the identity changed while
loading, stop the writer and retry with a stable file. Non-regular project
entries are not parsed; remove or replace them with a regular file.
User files are trusted policy and do not use these project-only identity rules.

## Examples

[Examples](../examples/sandbox.yaml) are templates subordinate to this reference.

| File | Actual additions |
|---|---|
| [Base](../examples/sandbox.yaml) | Commented options and path lists |
| [Strict](../examples/sandbox-strict.yaml) | Strict mode and cloud-sync blocks; detected harness state remains writable |
| [Paranoid](../examples/sandbox-paranoid.yaml) | Four restrictive scalars and cloud-sync blocks; still retains automatic harness grants |
| [Permissive](../examples/sandbox-permissive.yaml) | Explicit reference/data grants with scrubbing |
| [Cloud engineering](../examples/sandbox-cloud-eng.yaml) | Kubernetes, Docker, Helm grants; these may carry credentials and sockets |
| [Grok](../examples/sandbox-grok.yaml) | Grok-specific defense |

For untrusted review, use
`scode --trust untrusted --config examples/sandbox-paranoid.yaml codex`.
The preset supplies the extra suppression that config scalars cannot express.
Installed examples live under `PREFIX/share/scode/examples`, including
`$(brew --prefix)/share/scode/examples` for Homebrew.
