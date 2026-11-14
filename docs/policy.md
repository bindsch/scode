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
lookup. These are material runtime exceptions to deny-default. Strict mode
also permits metadata-only reads (`file-read-metadata`) of the home and of
every ancestor directory of a granted path, so a harness can stat and
canonicalize its way to a grant; contents outside grants stay denied.

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
| Project `allowed` / `allowed_ro` | Never authorizes access; redundant entries add no authority |
| Project grant | Reopens a project inside a built-in blocked parent; built-in and custom blocks inside the project stay blocked in both modes; a custom block covering the project requires an authoritative read or read-write grant |
| Internal command/preload grants | Cannot override retained custom blocks; the command exception applies only to default/platform blocks |
| Automatic harness state | Read-write; skipped under `untrusted`, outside effective HOME after symlink resolution, or when blocked; built-in blocks inside state remain denied |
| Explicit child allow | Can reopen a child of a blocked parent; allowing a parent also covers descendants |
| Grok mandatory blocks | Overlapping explicit allows are refused |
| Final project read-only rule | `--ro` remains effective even with a broader writable grant |
| Privilege-command restriction | Reasserted after all grants in this working tree; see below |

Order among `--allow`, `--allow-ro`, and `--block` flags does not determine
precedence. `--allow` grants reads and writes. Repeatable `--allow-ro PATH`
grants reads and execution while capping writes at read-only, including when
the project or another writable grant overlaps it. On macOS it emits
`file-read*` and `process-exec` grants followed by a `file-write*` denial;
Linux uses `bwrap --ro-bind`. The final privilege execution restriction still
applies. Use the narrowest subtree required.

Read-only grants work in strict mode and can reopen a CLI block, a built-in
block, or the account-home block created by a synthetic HOME. They do not
remove write denials. User config `allowed_ro:` has the same read authority,
except that an overlapping CLI block wins in either ancestor direction.
Project `allowed_ro:` entries are ignored. Paths resolve against the selected
project, follow symbolic links, and undergo the same validation as `--allow`.
Missing read-only paths are refused on both backends, including in dry-run;
create them before granting access. Dry-run shows the resolved grants.
Blocks nested inside a read-only grant remain blocked. An explicit grant at
or below a block can reopen that path, but does not lift deeper blocks.

For example, `--strict --block /store --allow-ro /store/bin/tool` can execute
that tool without allowing it to change itself or read siblings in `/store`.

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

Strict mode applies built-in blocks inside every grant. Deny-default already
hides a built-in block outside the grants, but a grant that covers one used to
reopen it: through v0.6.5, `scode --strict -C ~` left `~/.ssh` readable
because it lay inside the project. Now a built-in block with any spelling
strictly inside the project, an explicit allow, or detected harness state is
denied again after that grant on macOS and masked after the bind on Linux.
This includes a block whose link resolves into the grant from outside it,
including a system read grant or the private per-invocation macOS temp grant.

An explicit allow of the block, its link name, its resolved target, or an
ancestor lifts it, as in default mode. An explicitly allowed child of a block
is granted again after the block. Automatic harness state cannot lift a
built-in block, even when a state symlink points inside it. A project that is
itself a built-in block, or lies inside one, is granted: selecting the project is an
explicit choice, as in default mode. A custom block that covers the whole
project is refused unless an authoritative grant reopens it. A read-only
grant at or below that block can reopen project reads while keeping the
project read-only. A broader read-only grant does not lift nested custom blocks.

The project exception covers only the project and its descendants, including
under automatic harness state: with `~/.aws -> ~/.codex/aws`, selecting
`~/.codex/aws/project` grants that project while `~/.codex/aws/credentials`
stays blocked despite the broader `~/.codex` state grant. Selecting
`~/.codex/aws` itself grants that entire project. Blocks strictly inside the
project still apply. Every later re-denial preserves this exception, including
when a different spelling of the block lies inside a restored child allow.
macOS excludes the project from its built-in parent's denial predicate. Linux
masks built-in parents, restores only the project, then masks blocked children.

On Linux, strict mode also masks custom blocks inside detected harness state
and system read grants; through v0.6.5 they were masked only inside the project
or an explicit allow. Read-only project binds follow all
ancestor grant restorations and precede the final Linux masks, so `--ro`
cannot reopen a blocked child or be hidden by a writable ancestor in either
mode. Only child exceptions that cannot cover the project are restored after
these masks. macOS applies its final project write denial after all restores.
Missing targets on read-only mounts need no mask: they are absent and cannot
be created there.

The command executable and scode's injected Node preload have exact-file
exceptions after built-in blocks on both platforms. The preload is granted
read-only, including its resolved target and any temporary space-free alias;
its directory and sibling files remain blocked. macOS also permits ancestor
metadata so Node can resolve the preload path. Custom blocks remain
authoritative: a custom block covering the preload disables its injection,
and one covering the command suppresses the command exception. If an
installation path contains spaces and a retained custom block covers the
temporary preload alias (for example, `--block /tmp`), scode refuses the
launch before creating the link or emitting policy. Use an installation
path without spaces or revise the custom block to launch.

Both platforms use the same emission rule after resolving policy sources:
grants expose their selected paths, retained blocks restrict those grants,
and authoritative child allows reopen only their selected children. A later
restoration must preserve every retained block within it and the built-in
project exception. Final guards apply this same rule; they add no authority.
On macOS, each block denial excludes its authoritative child allows in its
predicate. Repeating the denial therefore cannot revoke those exceptions;
a different retained block still applies its own predicate. This also covers
chains whose intermediate link lies inside a restored allow and whose target
contains a separately allowed file.
The project remains read-only under `--ro`. Exact command and preload
exceptions follow the blocks, subject to custom policy, and cannot add write
access. They also cannot revoke writes granted by the project or an explicit
allow: Linux adds an exact read-only bind only when the preceding mounts hide
the file. Metadata-only ancestor access on macOS supports path resolution.
The final privilege-command restriction overrides every execution grant.

The pure reference model in `test/policy_model.js` expresses these decisions
without inspecting emitted rules. `test/19_generated_policy.bats` compares it
with full CLI dry-runs on both backends. The generator covers link chains,
block spellings, child/ancestor/target grants, automatic state, runtime files,
strict mode, and read-only projects. Separate evaluators apply SBPL rules in
order and Linux mounts in order, including parent mounts that hide earlier
child mounts. Queries concern existing synthetic host files, not files created
inside private tmpfs mounts or macOS metadata-only access.
The matrix includes projects nested inside resolved built-in targets and
queries sibling credentials under automatic state grants.

macOS denies execution of basenames `sudo`, `su`, `login`, `doas`, and
`pkexec`. Linux masks the installed files `LINUX_PRIVILEGE_TOOLS` names in
[scode](../scode): those in `/usr/bin`, the classic `sudo.ws`, and the sudo-rs
names that Ubuntu 26.04 installs (`sudo-rs`, `su-rs`, and the binaries in
`/usr/lib/cargo/bin`).

On Linux every mask is mounted on the path with all symbolic links resolved.
bubblewrap cannot mount on a link: it resolves an absolute link against its
staging root and refuses to start. A mount on the resolved target covers every
name that leads to it, such as `/usr/bin/sudo` through `/etc/alternatives/sudo`
on Ubuntu 26.04, or a dotfile manager's `~/.aws` link. A missing privilege tool
or a dangling link to one is skipped. A dangling link in a block list is
blocked at its target path, or at the topmost missing directory above the
target, so neither the target nor its parents can be created in the sandbox.

On macOS Seatbelt matches a rule against the path the kernel resolved, so a
deny on a link name alone does not protect the link's target. Through v0.6.4,
with `~/.aws` linked to `~/dotfiles/aws`, `cat ~/dotfiles/aws/credentials`
printed the secret inside the sandbox. Every macOS deny rule now names each
spelling of the blocked path: the link name as written, each path met while
its links resolve (a link in the final component, in an ancestor such as
`~/.config`, or in a chain of links), and the canonical target. A dangling link
is denied at the target path its creation would use; a link cycle is denied
under every name in it. A custom block keeps its spelling before resolution as
well as its canonical path. Later grants (the project override, `~/Library`
carve-outs, and child allows) are followed by a deny for any block spelling
inside them, so a grant never reopens a block's resolved target. An allow of a
built-in block's link name or of its resolved target lifts that block on both
platforms, as an allow of the literal path already did.
For a custom block, only an allow covering its resolved target lifts the
block. Allowing an ancestor of its written link name does not lift it when
the target lies outside that ancestor.
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

## macOS strict descendant teardown

Seatbelt has no session lifetime boundary. In strict mode, scode adds a
unique pair of existing marker files to the profile: one denies reads and
the other permits reads. Both files and the helper snapshot are protected
against sandboxed writes. The helper runs outside Seatbelt at exit, before
scratch accounting and removal. It enumerates processes and uses
`sandbox_check` to identify this pair of permissions, regardless of parent,
process group, `setsid`, or double fork. It sends SIGTERM, rescans during a
one-second grace period, then sends SIGKILL and rescans for up to one second.
Signals use Darwin audit tokens with PID generations, so PID reuse cannot
redirect a signal to a different process.

Every launch checks the API against a sandboxed probe and the unsandboxed
parent, including rejection of a stale PID generation. This requires the
installed `lib/scode/strict-teardown.py` and `/usr/bin/python3`. If identity
or generation-checked signaling is unavailable, scode warns that detached
descendants may survive. It does not fall back to process names, environment
markers, or process-group guesses. An exit-time failure also warns and keeps
the command's exit status.

Runtime tests on macOS 27.2 (26B123, arm64) killed a TERM-ignoring,
double-forked `setsid` descendant after normal exit, a logged run, and parent
TERM and QUIT. They also preserved an unrelated process and a concurrent scode
sandbox. These tests do not establish a kernel lifetime boundary: SIGKILL
of scode prevents its exit trap, API failures can prevent identification,
and continuous forking or uninterruptible processes can exceed the bounded
cleanup window. A process whose sandbox no longer exposes the identifying
permission pair cannot be classified by this mechanism. Default mode has
no descendant sweep. macOS versions other than the tested one require their
own runtime evidence.
