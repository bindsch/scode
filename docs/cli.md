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
| `--allow-ro PATH` | Grant recursive reads and execution with a write cap, including in strict mode |
| `--allow-staged PATH` | macOS 0.6.8+: grant read-write to the exact file and siblings named `PATH.tmp.<8 hex digits>` |
| `--strict` | Deny-default filesystem policy with system, project, scratch, and detected harness grants |
| `--trust LEVEL` | `trusted`, `standard`, or `untrusted`; see [presets](policy.md#trust-presets) |
| `--config FILE` | Select user configuration |
| `--scrub-env` | Remove variables matching the credential and injection patterns |
| `--keep-env NAME[,NAME...]` | Exempt exact valid names from scrubbing, preserving empty values; injection names remain refused |
| `--no-credential-sync` | Compatibility no-op for 0.6.8; scode never reads, copies, checks, or changes a harness login |
| `--login-store` | Opt in to macOS `claude`/`agy` login-store access; off by default; see the exposure below |
| `--no-login-store` | Suppress login-store grants; wins over CLI/user opt-in regardless of order. Explicit path grants retain their file authority, except for the login keychain directories and the user keychains the preference file records, which stay closed |
| `--log FILE` | Replace FILE with private stderr capture; create missing parent directories |
| `--dry-run` | Print generated policy/command without launching |

## Parsing

Options stop at the first command token or `--`. Arguments after it belong to
the command, even if they look like scode flags. `--option=value` and bundled
short flags are unsupported. Values must be separate arguments.

`--cwd`, `--config`, `--log`, and `--trust` are singletons; repeats fail.
`--block`, `--allow`, `--allow-ro`, `--allow-staged`, and `--keep-env` accumulate. Repeated `--ro` and
`--rw` use the last value. Other Boolean flags are idempotent.
Explicit scalar flags override trust presets regardless of their position.
The login-store grant is an exception: `--trust untrusted` always suppresses it.

`--login-store` (user config: `login_store: true`) grants `~/Library/Keychains`
read-write so the harness can refresh its own item, and
`~/Library/Preferences/com.apple.security.plist` read-only when it exists.
`--no-login-store`, user/project `no_login_store: true`, or an overlapping block
on either path suppresses the whole grant. Project config cannot enable it.
The invoked harness name must resolve to a regular executable outside the
project; version-number targets qualify, interpreter entry scripts and shell
`-c` wrappers do not.

Every process in an enabled sandbox can read Keychain items whose access list
trusts `/usr/bin/security` without a dialog, including the harness login with its
refresh token and tokens stored by other tools. It can read and copy out
`login.keychain-db`, encrypted under the account's login password, which can then
be attacked offline. It can create, modify or delete files in the keychain
directory. It cannot change the default keychain or search list through the
read-only preference file. Without the grant, a sandboxed `claude` on macOS falls
back to `~/.claude/.credentials.json` if one exists and is accessible; scode does
not inspect that file. See [security](security.md) for manual-grant precedence.

Unless the grant is applied and `~/Library/Keychains/login.keychain-db` exists
under the sandbox HOME, the grant is not made and every macOS profile ends with a
deny of Mach lookups for `com.apple.authd`, `com.apple.security.agent`, `com.apple.security.agent.login`, `com.apple.security.authhost`, and `com.apple.securityd.xpc`, and a deny of the login keychain directories. This
applies to every command and mode. No authorization session can then be made, so a
call that needs one fails with an error; that includes the store that would ask
for a missing default keychain.
`com.apple.SecurityServer` stays reachable; programs load the system root
certificates through it. An explicit `--allow` of the Keychains directory has no
effect without the grant. See
[keychain services](security.md#keychain-services-on-macos).

`--allow-staged` refuses symlinked base files. Its regex matches without regard
to case across the whole staged path, including directory and base names, even
on a case-sensitive volume. See [staged grants](policy.md#precedence).

`audit` accepts one logfile, optionally preceded by `--watch` or `-w`.
Use `scode -- audit ...` to launch a command literally named `audit`.

## Path resolution

| Input | Relative base and handling |
|---|---|
| `--cwd DIR` | Invoking directory; must resolve to an existing directory |
| `--block`, `--allow`, `--allow-ro`, `--allow-staged`, config `blocked` / `allowed` / `allowed_ro` / `allowed_staged` | Selected project, including entries from a user config elsewhere |
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
| Invalid arguments/config, unsafe paths, missing engine/command, or setup failure | 1 |
| Engine launches | Its exit status, including its own handled-signal status |
| Fatal signal | Usually `128 + signal number`; see [signal table](platforms.md#signals) |
| QUIT caught by scode | 131; the engine can survive a PID-directed QUIT |
| Requested logging fails | Nonzero; a successful engine status becomes 1 |
| Accounting fails | Warning or dropped record; run status unchanged |

An engine's own launch failure can return its own nonzero status. Exit 0 does
not prove that a command avoided denied operations, that every denial was
logged, or that accounting succeeded.
