# Filesystem and network policy

## Platform and mode matrix

Permissions below remain subject to explicit blocks, grants, and final
invariants in the precedence table.

| Resource | macOS default | macOS strict | Linux default | Linux strict |
|---|---|---|---|---|
| Initial filesystem view | Allow-default minus selected blocks | Deny-default with runtime exceptions | Selected mounts; other host paths absent | Selected system mounts; HOME not broadly mounted |
| Project | Read-write, or read-only with `--ro` | Same | Same | Same |
| System | Accessible under host permissions | Read-only system paths listed below | Existing `/usr /opt /lib /lib64 /bin /sbin /etc` read-only | Same |
| HOME | Accessible except blocks | Only explicit and detected harness grants | Bound read-write except masks | Only explicit and detected harness grants |
| Temporary storage | Shared paths remain reachable; private TMPDIR provided | Private per-run scratch; shared temp denied unless granted | Private `/tmp` tmpfs | Private `/tmp` tmpfs |
| Detected harness state | Usually already reachable unless blocked | Automatic read-write grant | Usually already reachable unless blocked | Automatic read-write bind, only if it exists |
| Runtime sockets | Subject to profile/host permissions | Broad Mach lookup remains | Validated XDG runtime directory when network is on | No automatic XDG runtime bind |

macOS strict permits reads from `/usr`, `/opt`, `/System`, `/Library`,
`/private/var/db`, `/private/var/run`, `/private/var/select`,
`/private/etc`, `/dev`, `/bin`, `/sbin`, and `/etc`. It imports Apple's
private `system.sb` and allows process execution/fork, sysctl reads, and Mach
lookup. These are material runtime exceptions to deny-default.

Linux supplies private `/proc` and `/dev`. Its default runtime bind requires
`XDG_RUNTIME_DIR` to resolve to `/run/user/$UID`, owned by the user with mode
0700. Strict mode and `--no-net` omit that automatic bind.

## Trust presets

| Preset | Scalar settings | Additional behavior |
|---|---|---|
| `standard` | No overrides; same as omitting `--trust` | Normal config precedence |
| `trusted` | Read-write project, network on, strict off, scrub off | Default path blocks still apply |
| `untrusted` | Read-only project, network off, strict on, scrub on | Disables automatic harness-state grants and Claude credential copying |

The four explicit flags `--strict --no-net --scrub-env --ro` do not disable
automatic harness grants or copying. They are not equivalent to `untrusted`.

Presets override config scalars for their four settings. Explicit CLI scalar
flags override presets. Config path grants still apply. Selecting a credential
directory as the project can expose it even under `untrusted`.
For unknown code, start with `scode --trust untrusted --cwd ./review -- command`
and inspect `--dry-run` before adding grants.

## Precedence

Scalar priority is explicit CLI, preset, user config, restrictive project
config, environment, then defaults. Grok defense forces strict and scrub on
after those choices for a detected Grok command.

Path policy has separate rules; it is not a single last-option-wins list:

| Source or invariant | Effect |
|---|---|
| Built-in/platform blocks | Removed when covered by an explicit CLI or user-config allow |
| User/project blocks | Retained unless explicitly reopened by a user-config or CLI allow |
| CLI blocks | Beat overlapping config allows in either ancestor direction; CLI allows can make exceptions |
| Project `allowed` | Never authorizes access; redundant entries add no authority |
| Project grant | Reopens a project inside a built-in blocked parent; retained custom blocks covering the entire project cause refusal |
| Internal command/preload grants | Cannot override retained custom blocks; the command exception applies only to default/platform blocks |
| Automatic harness state | Read-write; skipped under `untrusted`, outside effective HOME after symlink resolution, or when custom-blocked |
| Explicit child allow | Can reopen a child of a blocked parent; allowing a parent also covers descendants |
| Grok mandatory blocks | Overlapping explicit allows are refused |
| Final project read-only rule | `--ro` remains effective even with a broader writable grant |
| Privilege-command restriction | Reasserted after all grants in this working tree; see below |

Order among `--allow` and `--block` flags does not determine precedence.
A path grant permits read and write; there is no arbitrary read-only allow flag.
Use the narrowest subtree required.

On Linux, paths must exist to be bound. In releases through v0.6.0, default-mode
allows only rebind children of blocked paths; they do not introduce arbitrary
host subtrees. This working tree fixes that limitation. Strict mode already
binds existing explicit paths. Missing strict allows warn and are not created.

## Default blocks and project overrides

The canonical exact path lists are `DEFAULT_BLOCKED`, `DARWIN_EXTRA_BLOCKED`,
and `LINUX_EXTRA_BLOCKED` in [scode](../scode). They protect named paths, not
all possible copies of sensitive data.

Common blocks include Documents, Desktop, Pictures, Downloads, Music, Movies,
Videos, SSH/signing keys, cloud/container credentials, password stores,
package/VCS tokens, and shell/database histories. macOS also blocks all of
`~/Library`, with no automatic Keychain/browser carve-outs. Linux adds
Mozilla, Chrome, Chromium, Brave, Thunderbird, Signal, Flatpak, and Snap state.

When effective HOME differs from account home, the latter is blocked as a whole.
Explicit grants and project selection still matter. Custom blocks inside the
project are reasserted after the project grant.

macOS denies execution of basenames `sudo`, `su`, `login`, `doas`, and
`pkexec`. Linux masks existing corresponding files in `/usr/bin`.
Releases through v0.6.0 could reopen these with later grants; the working tree
reasserts them after grants. These restrictions do not identify renamed copies
or every privilege mechanism and do not replace the OS user boundary.

## Network and other authority

Network access is on by default. `--no-net` denies macOS network operations or
creates a Linux network namespace. Nonstandard inherited file descriptors are
closed. Standard streams and explicitly allowed pathname Unix sockets can still
carry data or authority. A Docker socket grant, for example, gives access to
the service behind that socket. Read-only project access does not make the
entire sandbox read-only.
