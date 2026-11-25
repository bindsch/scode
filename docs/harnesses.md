# Harness detection and authentication

Recognition selects state paths. It does not certify a vendor's authentication
flow, runtime compatibility, or safety. Unknown commands can run with a warning.

## Detection and state

The command executable is resolved and canonicalized before detection.
A trailing `.exe` is ignored for harness recognition. Supported transparent
wrappers include `env`, `nice`, `timeout`, `command`, `stdbuf`, `ionice`,
`taskset`, and shell `-c` forms. Parsing is conservative, not full shell
evaluation. An argument such as `echo claude` does not select Claude state.

If the basename is unknown, detection checks the full path for a supported
`node_modules` package directory: `@github/copilot`,
`@earendil-works/pi-coding-agent`, `@anthropic-ai/claude-code`, or
`@openai/codex`. Resolved entry scripts such as Copilot's `npm-loader.js`
and pi's `dist/bundle/cli.js` select the mapped harness name and state grants.
An unrelated `cli.js` remains unknown.

A standalone executable named `agent` is unknown. An executable symlink named
`agent` resolving to `cursor-agent` is recognized by its canonical name.
Detection of names inside wrapper text does not establish binary identity.
Shell aliases are interactive conveniences and do not enforce sandbox use.

Strict mode automatically grants these paths read-write access:

| Command | Paths under effective HOME |
|---|---|
| `opencode` | `~/.config/opencode`, `~/.local/share/opencode` |
| `claude` | `~/.claude` |
| `codex` | `~/.codex` |
| `goose` | `~/.config/goose` |
| `gemini`, `agy` | `~/.gemini` |
| `droid` | `~/.factory` |
| `qwen` | `~/.qwen` |
| `codemux` | `~/.codemux`, `~/.config/codemux` |
| `pi` | `~/.pi/agent` |
| `aider` | `~/.aider`, `~/.aider.conf.yml` |
| `amp` | `~/.config/amp`, `~/.amp` |
| `crush` | `~/.config/crush`, `~/.local/share/crush` |
| `cursor-agent` | `~/.cursor` |
| `copilot` | `~/.copilot`, `~/.cache/copilot` |
| `cn` | `~/.continue` |
| `kimi` | `~/.kimi-code`, `~/.kimi` |
| `openhands` | `~/.openhands` |
| `cline` | `~/.cline` |
| `kiro-cli` | `~/.kiro` |
| `auggie` | `~/.augment` |
| `grok` | `~/.grok` |

These grants are disabled by `--trust untrusted` and suppressed by custom blocks.
Symlinks resolving outside HOME are ignored. Linux binds only existing state
paths. macOS rules can permit creation of state within the named subtree.
Environment-selected roots such as `GROK_HOME` are not automatically granted;
use an explicit allow for a reviewed custom location.

Copilot's `~/.cache/copilot` grant is cross-platform. Its macOS primary cache
under `~/Library/Caches/copilot` remains blocked unless explicitly allowed.
On macOS, `claude` and `agy` can opt in to the login-store grants described below.
No broad macOS Library grant is added for any harness.
DeepSeek Harness (`dsh`) has no verified state-path entry.

Writable state lets harnesses persist settings and rotated OAuth credentials.
Every program launched within that sandbox can potentially read those
credentials. State access also permits modification. See [policy](policy.md)
for project and explicit-grant exceptions.

## Claude Code on macOS

scode never reads, copies, scrubs, backs up, or changes a harness login. It does
not invoke a Keychain tool, inspect credential files, refuse a launch based on
their contents, or tell the user to log in based on a credential guess.
Existing `~/.claude/.credentials.json` files and backups under
`~/Library/Application Support/scode/credential-backups` are left alone.

Login-store access is off by default. `--login-store` or user-config
`login_store: true` opts in for normal and strict macOS runs that launch
`claude` or `agy` directly or through the env form below. `~/Library/Keychains` becomes read-write so the harness can
rewrite its own item when its token refreshes.
`~/Library/Preferences/com.apple.security.plist` is read-only when it exists;
creating it when absent is denied. Every process in that sandbox can read
Keychain items whose access list trusts `/usr/bin/security` without a dialog.
This includes the harness's login and refresh token, and tokens other tools
stored through `security`, for example a GitHub CLI token. Every process can read
and copy out `login.keychain-db`, encrypted under the account's login password,
which can then be attacked offline. It can create, modify or delete files in the
keychain directory. It cannot change the default keychain or search list through
the read-only preference file. Other Library paths remain blocked. The launcher never reads or copies a
login: one login store means scode cannot create a stale refresh-token copy.

The invoked name must be `claude` or `agy` (optionally `.exe`) and its resolved
target must be a regular executable outside the project. Native installs such as
`~/.local/bin/claude -> ~/.local/share/claude/versions/2.0.99` and Homebrew targets
ending in `bin/claude.exe` qualify. Interpreter entry scripts and wrappers,
including shell `-c` strings, do not qualify, with one exception: the harness
run as `/usr/bin/env` with nothing but `HOME` and `XDG_*_HOME` assignments and
then its absolute path, the form a caller uses to give it a private home. A declined grant reports
the reason and both paths with their access modes. Redirected login-store paths
are not automatically granted. Both normal and strict modes report granted paths.
`--no-login-store` (user config: `no_login_store: true`), an overlapping `--block`,
or `--trust untrusted` suppresses the whole grant even after opt-in, regardless
of flag order. CLI, user-config, and project-config blocks on either path apply.
Project `login_store: true` cannot enable access; project `no_login_store: true`
can suppress it. Without access, the harness cannot use a Keychain login.
A sandboxed `claude` on macOS falls back to `~/.claude/.credentials.json` if one
exists and is accessible; scode does not inspect that file. Explicit grants
retain their documented precedence. See [security](security.md) for exposure
and the exact access a manual `--allow` provides.

`/usr/bin/security` remains executable inside the sandbox, and `securityd`
(`com.apple.SecurityServer`) stays reachable for certificate loading. `com.apple.authd`, the security agent names, and `com.apple.securityd.xpc` are
reachable only when the login-store grant is applied and
`~/Library/Keychains/login.keychain-db` exists under the sandbox HOME (for a
harness given another HOME through env, that HOME's `Library/Keychains` must be the same directory;
see [security](security.md)). Otherwise
the grant is not made, the profile ends with a deny of those Mach lookups and of
the login keychain directories, and a call that needs an authorization session
fails with an error ([limits](security.md#keychain-services-on-macos)). An explicit `--allow` of the Keychains directory has no effect without the grant.
scode does not initiate authentication or password dialogs. With the grant
applied, a harness or macOS can still display one. See
[keychain services](security.md#keychain-services-on-macos).

`--no-credential-sync` is accepted as a compatibility no-op for 0.6.8.
It neither inspects nor changes authentication. Login compatibility still
depends on the harness and the user's store.

For explicit file-based state access, macOS `--allow-staged` / user
`allowed_staged` grants a base file and its `.tmp.<8 hex digits>` siblings for
atomic replacement. Symlinked base files are refused. Matching ignores case
across the whole staged path, including directory and base names, even on
case-sensitive volumes. See [policy](policy.md#precedence).


## Cursor Agent on macOS

Cursor Agent 2026.10.22 uses Keychain services `cursor-access-token`,
`cursor-refresh-token`, and `cursor-api-key`, with account `cursor-user`.
Its `~/.cursor/agent-cli-state.json` and `~/.cursor/cli-config.json` files
hold state and configuration, not the login tokens.

The macOS `~/Library` block hides Keychain storage under both `standard`
and `trusted`. The existing `cursor-agent` state grant for `~/.cursor`
does not restore a Keychain login. Scode has no per-service Keychain grant;
a filesystem allowance for the login Keychain would expose unrelated items.
No additional Keychain allowance is provided for Cursor.

This Cursor version supports a file credential store. The operator can
select it when logging in outside scode:

```sh
AGENT_CLI_CREDENTIAL_STORE=file cursor-agent login
```

Use the same selection when launching under the standard sandbox:

```sh
AGENT_CLI_CREDENTIAL_STORE=file scode --trust standard --ro cursor-agent
```

On macOS this selects `~/.cursor/auth.json`, which Cursor writes with mode
0600. A Keychain login does not populate that file automatically. The existing
harness state grant permits access, including token updates. Programs inside
the sandbox can read the file's credentials. No reinstall is needed for this
alternative. Codemux automatically selects this store for sandboxed headless
runs on macOS when the file exists. An explicit store override is a codemux
option (`codemux run --pass-env AGENT_CLI_CREDENTIAL_STORE`), not an scode flag.

## Antigravity

The 2026-10-12 integration observation recorded macOS Antigravity using a
generic-password Keychain item through go-keyring and `/usr/bin/security`,
rather than a file credential store. The v1.3.1 state-path inspection identified
`~/.gemini/antigravity-cli`, shared `~/.gemini/config`, and root state files.
A help command that writes no files proves only that help invocation's behavior.

Normal and strict macOS `agy` launches can opt in to the same login-store grants
as Claude, in addition to the normal `~/.gemini` state access. Antigravity uses its own login Keychain;
scode does not create a credential file or a private mirror Keychain.
`--trust untrusted` does not receive those automatic grants.
