# Command-line reference

```text
scode [options] [--] <command> [args...]
scode audit [--watch|-w] <logfile>
```

With no command, scode runs `opencode`. Any command can run; detection adds
harness-specific state access, not a requirement to use a known harness.

## Options

| Option | Behavior |
|---|---|
| `-h`, `--help` | Print help and exit |
| `-V`, `--version` | Print the launcher version and exit |
| `-n`, `--no-net` | Disable IP networking; see socket limits in [policy](policy.md) |
| `-C DIR`, `--cwd DIR` | Select project and working directory; default invoking directory |
| `--ro` / `--rw` | Project read-only / read-write; default read-write |
| `--block PATH` | Add a file or directory block |
| `--allow PATH` | Request recursive read-write access; subject to [precedence](policy.md#precedence) |
| `--strict` | Deny-default filesystem policy with system, project, scratch, and detected harness grants |
| `--trust LEVEL` | `trusted`, `standard`, or `untrusted`; see [presets](policy.md#trust-presets) |
| `--config FILE` | Select user configuration |
| `--scrub-env` | Remove variables matching the credential and injection patterns |
| `--keep-env NAME[,NAME...]` | Exempt exact valid names from scrubbing, except refused injection names |
| `--no-credential-sync` | Disable macOS Claude Keychain copying; existing authentication can work, and mirrored-refresh-token refusal still applies |
| `--log FILE` | Replace FILE with private stderr capture; create missing parent directories |
| `--dry-run` | Print generated policy/command without launching or copying credentials |

## Parsing

Options stop at the first command token or `--`. Arguments after it belong to
the command, even if they look like scode flags. `--option=value` and bundled
short flags are unsupported. Values must be separate arguments.

`--cwd`, `--config`, `--log`, and `--trust` are singletons; repeats fail.
`--block`, `--allow`, and `--keep-env` accumulate. Repeated `--ro` and
`--rw` use the last value. Other Boolean flags are idempotent.
Explicit scalar flags override trust presets regardless of their position.

`audit` accepts one logfile, optionally preceded by `--watch` or `-w`.
Use `scode -- audit ...` to launch a command literally named `audit`.

## Path resolution

| Input | Relative base and handling |
|---|---|
| `--cwd DIR` | Invoking directory; must resolve to an existing directory |
| `--block`, `--allow`, config `blocked` / `allowed` | Selected project, including entries from a user config elsewhere |
| `--config`, `SCODE_CONFIG` | Invoking directory |
| `--log FILE` | Invoking directory; destination symlink is replaced, not followed |
| `audit FILE` | Invoking directory; shell expansion applies |
| `SCODE_ACCOUNT_FILE` | Invoking directory; parent must exist; sink symlinks rejected |
| Command containing `/` | Selected project when relative; resolved executable is used for launch |
| Command without `/` | Caller PATH; executable is canonicalized before launch |

Policy paths expand a leading `~` or `~/` against effective HOME and resolve
symlinks. They do not expand variables, globs, or commands in config values.
Output paths retain the final path component so the log writer can replace a
destination symlink safely. See [configuration](configuration.md) for validation.
Policy and option paths reject control characters, including embedded newlines.

## Environment

| Name | Values / purpose |
|---|---|
| `SCODE_CONFIG` | User config selector; `--config` wins |
| `SCODE_NET` | `on` (default) or `off` |
| `SCODE_FS_MODE` | `rw` (default) or `ro` |
| `SCODE_ACCOUNT_FILE`, `SCODE_ACCOUNT_ID` | [Accounting](accounting.md) sink and optional identifier |
| `HOME` | Effective home: absolute, existing, user-owned, not root |
| `TMPDIR` | macOS scratch-parent candidate, subject to ownership/location validation |
| `XDG_RUNTIME_DIR` | Conditional Linux default-mode runtime mount; see [policy](policy.md) |

The default config comes from the independently discovered account home.
Changing HOME does not change that default. If account discovery fails,
effective HOME is the fallback. `_SCODE_PLATFORM` is a testing override for
policy rendering, not a way to run another platform's sandbox.

## Exit statuses

| Situation | Result |
|---|---|
| Help, version, successful dry-run or batch audit | 0 |
| Invalid arguments/config, unsafe paths, missing engine/command, setup or credential refusal | 1 |
| Engine launches | Its exit status, including its own handled-signal status |
| Fatal signal | Usually `128 + signal number`; see [signal table](platforms.md#signals) |
| QUIT caught by scode | 131; the engine can survive a PID-directed QUIT |
| Requested logging fails | Nonzero; a successful engine status becomes 1 |
| Accounting fails | Warning or dropped record; run status unchanged |

An engine's own launch failure can return its own nonzero status. Exit 0 does
not prove that a command avoided denied operations, that every denial was
logged, or that accounting succeeded.
