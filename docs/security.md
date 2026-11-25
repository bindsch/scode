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
| No authorization session from the sandbox (the dialog for a missing default keychain cannot be requested) and the login keychain directories closed | Every macOS run without an applied login-store grant and a resolvable login keychain |
| Read-only project | `--ro`, config `fs_mode: ro`, or untrusted preset |
| IP network restriction | `--no-net`, config `net: off`, or untrusted preset |
| Fixed engine lookup and closed nonstandard inherited descriptors | All launched runs |

Default mode exposes harness state and ambient environment credentials unless
separately restricted. Strict mode grants detected harness state read-write.
On macOS, login-store access is off by default. `--login-store` or user-config
`login_store: true` opts in for `claude` and `agy`, launched directly or through the env form described below, in normal and
strict modes. `~/Library/Keychains` becomes read-write so the harness can rewrite
its own item when its token refreshes. `~/Library/Preferences/com.apple.security.plist`
is read-only when it exists; the grant never permits creating it when absent.
The invoked name must be the harness name (optionally `.exe`), resolving to a
regular executable outside the project. Native version-number targets and
Homebrew `bin/claude.exe` targets qualify. So does a harness run through
`/usr/bin/env` when env is given nothing but `HOME` and `XDG_*_HOME`
assignments followed by the harness's absolute path (one without `=`), which is
how a caller gives the harness a private home. A `HOME` given there must be an
absolute path whose `Library/Keychains` is the same directory, with the same
`login.keychain-db`, must hold no
keychain preference file of its own (none, or a link to the same file), and must
not lie under a block; the profile then denies writing that preference path,
creating a missing directory above it, and removing the `Keychains` entry; the resolved binary
path must not hold `=` either; env then runs that resolved binary; and in strict
mode the caller grants the harness executable itself, as for any wrapped
command. Interpreter entry scripts and shell
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
refresh token in it. Explicit `--allow` retains its documented file authority, with one exception:
`--allow "$HOME/Library/Keychains"`, or an `--allow` of a user keychain the
preference file records, has no effect without the applied login-store grant,
because the final rule of the profile denies those paths (see [keychain services](#keychain-services-on-macos)).
`--allow-ro "$HOME/Library/Preferences/com.apple.security.plist"`
grants that existing file read-only. Manual writable grants can exceed the
login-store grant's restrictions.

scode never calls a Keychain tool, reads login contents, writes credential
files, or creates, prunes, or restores credential backups. It does not guess
whether a user is logged in. The launcher never reads or copies a login: the
harness uses one login store, so scode cannot create a stale refresh-token copy.
Existing copies are left alone. `/usr/bin/security` stays executable in the
sandbox. Whether it can reach a keychain is decided by the rule below.

## Keychain services on macOS

File rules alone do not keep a sandboxed process away from the keychain. With
`~/Library/Keychains` hidden, Security.framework in the child finds no default
keychain. A store then asks the authorization daemon to create one, and macOS
shows "A keychain cannot be found to store ..." on the owner's screen. Other
keychain and authorization calls can raise other dialogs the same way.

scode therefore makes one decision per launch, "keychain reach: yes or no", and
derives two rules from it:

- the login-store file grant described above;
- a final `(deny mach-lookup ...)` rule for the global name `com.apple.authd`,
  plus `com.apple.security.agent`, `com.apple.security.agent.login`,
  `com.apple.security.authhost`, and `com.apple.securityd.xpc` (the
  data-protection keychain) as defense in depth, followed by a deny of the
  login keychain directories.

A dialog is requested through an authorization session, and only
`com.apple.authd` makes one. With it denied, `AuthorizationCreate` fails inside
the sandbox (measured: status -60008), so the request for "A keychain cannot be
found to store ..." cannot be made.

`com.apple.SecurityServer` (securityd) is left reachable on purpose. Programs
that load the system root certificates through the keychain API, such as Codex
and anything built on `rustls-native-certs`, open the certificate keychains
through it, and all their HTTPS requests fail without it; scode 0.6.9 denied it
and broke them. What keeps the login keychain away from a sandbox without the
grant is a file rule instead. The last rule of the profile denies reads and
writes of the login keychain directories: `~/Library/Keychains` under the HOME
of the run and under the account home, by every name their links give them. It
also denies each user keychain that `com.apple.security.plist` records as the
default keychain, the login keychain or in the search list, wherever it lies;
the keychains of the system domain are left readable, and a relative recorded
name is read from the project directory. The records are read with `/usr/libexec/PlistBuddy`, which every macOS
release has. A path that cannot be resolved with certainty, or that the profile
cannot carry, stops the launch when a file exists there; a recorded name with a
control character and no file is ignored, and so is one that names a directory. A recorded name ending in `.keychain` or
`.keychain-db` closes both names. It comes after every allow, so no `--allow`, project directory or link can
put the keychain files and the daemon that decrypts their items in the same
sandbox.

Keychain reach is yes only when the login-store grant is applied to the launched
command and `~/Library/Keychains/login.keychain-db`, under the HOME scode exports
to the child, exists as a regular file that still lies inside that directory
after links are resolved. When `com.apple.security.plist` records a default
keychain or a login keychain (element zero of its `DefaultKeychain` or
`LoginKeychain` array), each recorded keychain must also be an existing regular
file inside the same directory. A recorded name ending in `.keychain` that does
not exist stands for its `-db` file. An empty array means no such keychain and
counts as no. So does a first element without a non-empty string `DbName`:
macOS was observed to fall back to the login keychain there, but scode does not
rely on that. A recorded name that contains a control character, or that is neither
absolute nor `~/`-relative, counts as no. A macOS whose `plutil` cannot classify the file (before macOS 12) also counts
as no. A non-empty preference file that cannot be read stops the launch for
every command, with or without the grant: the final rule below must know which
keychains the file records. A preference file macOS itself would ignore (unparsable, or a
value that is not an array) records nothing. In every other case the file grant
is not made and the profile ends with the deny. That covers the default, `--no-login-store`, a
command that is not `claude` or `agy`, an ineligible target, `--trust untrusted`,
an overlapping block, and a HOME that holds no login keychain (for example a
private per-run HOME), with or without `--login-store`. `--strict` and `--ro` do
not enter the decision: the same rule applies in normal, strict and read-only
modes, so an applied grant keeps the services reachable there too. A declined
`--login-store` reports the reason for any command; a declined user-config
opt-in reports it for `claude` and `agy` launches.

The deny is the last rule of the profile. Seatbelt lets a filtered `mach-lookup`
deny win over the unfiltered allows scode emits (`(allow default)`, and
`(allow mach-lookup)` in strict mode). Only a later filtered Mach allow of the
same name could reopen it, and scode emits none. The file deny that follows it
is the last file rule, so an earlier allow of the same directory loses to it:
`--allow "$HOME/Library/Keychains"` without the login-store grant gives nothing.

With the deny in place, authorization calls made by any process in the sandbox
fail with an error (`AuthorizationCreate`, and with it `AuthorizationCopyRights`),
and so does a keychain call that needs one, such as the store that would ask to
create a default keychain. The login keychain cannot be opened, because its
files are hidden: `security` subcommands, keyring libraries and
`git-credential-osxkeychain` get an error for it. TLS trust evaluation uses
`com.apple.trustd`, which stays reachable. HTTPS requests were checked under
these rules with curl, Node, Bun, Python, git, URLSession, `uv --native-tls`,
and Codex.

A non-empty preference file that cannot be read stops the launch as well,
because it may record keychains the rule would miss.

The rule names paths, so a second final rule denies renaming or removing every
directory above one of them: a sandbox that was allowed to write a parent of the
keychain directory (`--allow "$HOME/Library"`) cannot give the files another
name.

Limits of this rule. A keychain file that is neither in those directories nor
recorded in the preference file is not known to scode and is readable wherever
the sandbox can read; so is a hard link to a keychain file that already exists
somewhere the sandbox can read. A sandboxed process can also send securityd
requests that need no keychain file, such as locking every keychain of the
login session, after which other applications ask for the password. scode 0.6.9
prevented those and broke certificate loading; 0.6.10 does not prevent them.
securityd can itself ask the owner about a keychain a
sandboxed process can read and asks it to open, for example to unlock it. The
login keychain is not readable there. A keychain file kept somewhere the
sandbox can read is: one inside the project, and the System keychain
(`/Library/Keychains/System.keychain`), which stays readable because
administrator-installed root certificates are loaded from it. With the grant
applied, the services are reachable, and a harness or macOS can display a
dialog, for example an access-list confirmation for an item.

Limits. The rule covers the launched command and every descendant, which
inherit the profile. It does not cover work a child hands to a process outside
the sandbox: default and strict macOS profiles still allow lookups of
LaunchServices (`open`), Apple Events (`osascript`), and the user launchd domain
(`launchctl`). A process started that way is not sandboxed and can use the
keychain. Linux is unchanged: bubblewrap has no Mach layer.

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
