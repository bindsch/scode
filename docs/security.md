# Security model

scode limits the OS authority of commands processing untrusted repositories,
prompts, tool output, hooks, and MCP data. A compromised harness is treated as
a command runner. Its readable files, writable files, credentials, network
connections, and open streams are the relevant authority.

| Protection | When it applies |
|---|---|
| Named personal/credential path blocks | Default and strict modes, subject to [path precedence](policy.md#precedence) |
| Deny-default filesystem view | Strict mode, including the untrusted preset; system/runtime exceptions remain |
| Restrictive-only project config | All modes |
| Ambient credential scrub | Explicit `--scrub-env`, untrusted preset, or detected Grok defense |
| No automatic harness-state or Keychain grants | Untrusted preset |
| Read-only project | `--ro`, config `fs_mode: ro`, or untrusted preset |
| IP network restriction | `--no-net`, config `net: off`, or untrusted preset |
| Fixed engine lookup and closed nonstandard inherited descriptors | All launched runs |

Default mode exposes harness state and ambient environment credentials unless
separately restricted. Strict mode grants detected harness state read-write.
On macOS, login-store access is off by default. `--login-store` or user-config
`login_store: true` opts in for directly launched `claude` and `agy` in normal and
strict modes. `~/Library/Keychains` becomes read-write so the harness can rewrite
its own item when its token refreshes. `~/Library/Preferences/com.apple.security.plist`
is read-only when it exists; the grant never permits creating it when absent.
The invoked name must be the harness name (optionally `.exe`), resolving to a
regular executable outside the project. Native version-number targets and
Homebrew `bin/claude.exe` targets qualify. Interpreter entry scripts and shell
`-c` wrappers do not. Redirected login-store paths are declined.
Both modes report the granted paths. Every process in that sandbox can read
Keychain items whose access list trusts `/usr/bin/security` without a dialog.
This includes the harness's login and refresh token, and tokens other tools
stored through `security`, for example a GitHub CLI token. Blocking `~/.config/gh`
does not protect a GitHub token stored this way. Every process can read and copy
out `login.keychain-db`, encrypted under the account's login password, which can
then be attacked offline. Every process can create, modify or delete files in the
keychain directory. It cannot change the default keychain or search list through
the read-only preference file. Writing, replacing, and creating that file are
denied by the sandbox. This is a directory grant, not a per-item Keychain grant.
Other Library paths remain blocked. `--no-login-store` (user config:
`no_login_store: true`), an overlapping `--block`, or `--trust untrusted` suppresses
the whole grant even after opt-in. Blocks from CLI, user config, and project
config apply to either path. Project `login_store: true` cannot enable access;
project `no_login_store: true` can suppress it. Opt-outs win regardless of flag
order. Without access, the harness cannot use a Keychain login. A sandboxed
`claude` on macOS falls back to `~/.claude/.credentials.json` if one exists and is
accessible; scode does not inspect that file or guard against an existing stale
refresh token in it. Explicit `--allow` retains its documented authority:
`--allow "$HOME/Library/Keychains"` grants that directory read-write only; it does
not grant the preference file. `--allow-ro "$HOME/Library/Preferences/com.apple.security.plist"`
grants that existing file read-only. Manual writable grants can exceed the
login-store grant's restrictions.

scode never calls a Keychain tool, reads login contents, writes credential
files, or creates, prunes, or restores credential backups. It does not guess
whether a user is logged in. The launcher never reads or copies a login: the
harness uses one login store, so scode cannot create a stale refresh-token copy.
Existing copies are left alone. The sandbox keeps
`/usr/bin/security` executable and `securityd` reachable for that purpose;
a harness or macOS may still initiate a password dialog.

Upgrade note: 0.6.7 scrubbed or refused a `~/.claude/.credentials.json` that held a
refresh token. 0.6.8 never inspects that file. If you have one from an older file
login, after confirming that your Keychain login works, remove the file yourself.
scode prints nothing about login state.

An allow, project choice, environment exemption, or socket grant can transfer
credentials or broad service authority. Configuration is not an authenticity
check on the command.

macOS `--allow-staged` / user `allowed_staged` grants a base file and its
`.tmp.<8 hex digits>` siblings. Symlinked base files are refused. The kernel
matches case-insensitively across the whole staged path, including directory and
base names, even on a case-sensitive volume. Case variants can therefore expose
distinct files there. See [policy](policy.md#precedence).

A cloud CLI can transmit anything it can read while its network is available.
scode cannot distinguish inference traffic from an unwanted upload to the same
encrypted origin. For no outbound source transfer, use an offline tool with
network disabled and no authority-bearing stream or socket grants.

The wrapper does not defend against kernel/engine vulnerabilities.
macOS uses deprecated sandbox-exec and broad compatibility allowances.
Linux depends on user namespaces and mount ordering. Disabling browser inner
sandboxes is another [explicit tradeoff](browsers.md#security-tradeoff).
[Logs](logging.md) and [accounting](accounting.md) are operational records,
not authenticated proof against a child that can modify their destinations.

Report vulnerabilities through the [disclosure policy](../.github/SECURITY.md).

## Research references

Links checked on 2026-10-13; these sources provide context, not additional
scode guarantees.

- [VS Code agent security](https://code.visualstudio.com/docs/agents/run/security)
- [Anthropic Sandbox Runtime](https://github.com/anthropics/sandbox-runtime)
- [MCP security best practices, 2026-07-28](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/security_best_practices)
- [Grok incident evidence and version limits](grok-defense.md)

The July report's Axios and NSA links returned access failures during the
documentation audit. That did not establish that they were dead. They are
not required evidence for the guarantees here; accessible primary references
above and in the Grok guide replace that dependency.
