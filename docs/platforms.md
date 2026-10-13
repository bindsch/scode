# Platforms and process behavior

## Verification matrix

The [CI workflow](../.github/workflows/ci.yml) declares:

| Environment | Node test matrix | Sandbox evidence required |
|---|---|---|
| GitHub `macos-15` | 22, 24, 26 | Real sandbox-exec tests without runtime-unavailable skips |
| GitHub `ubuntu-24.04` | 22, 24, 26 | Real bubblewrap tests after the user-namespace probe |

Runner labels do not pin an engine or architecture version. Each release's
evidence must record OS build, `uname -m`, Bash, Node, bubblewrap version on
Linux, and the sandbox-exec path plus OS build on macOS. Do not infer a tested
Debian family or a particular architecture from the Ubuntu label.

The old README mentioned macOS 26 manual use without a complete engine,
architecture, revision, or runtime-test record. That is historical context,
not a reproducible support claim. Current task evidence belongs in the
[dated rebuild report](archive/2026-10-13-docs-rebuild.md).

Production checks that the fixed engine path is executable, then launches it.
A present but unusable engine fails at launch. Capability probes in
`test/test_helper.bash` are test-only and can produce explicit skips.

## Temporary storage and sockets

See the [policy matrix](policy.md#platform-and-mode-matrix) for filesystem
differences. macOS creates private per-run scratch below a validated,
user-owned mode-0700 `/private/var/folders/.../T` parent, otherwise under
`/private/tmp`. Strict mode permits that directory while denying shared temp.
Default mode still allows other shared temp paths unless blocked.

Linux uses a private `/tmp` tmpfs. Scratch cleanup is best effort; descendants
that survive scode can continue running while cleanup is attempted.
[Accounting](accounting.md) measures only the macOS private scratch directory.

The macOS backend uses deprecated sandbox-exec and private `system.sb`
runtime allowances. Linux needs working user namespaces. Neither engine
protects against its own vulnerabilities or kernel exploits.

## Signals

scode and its engine share a process group so interactive stdin works.
The wrapper cannot reliably distinguish a signal sent to its PID from one
sent to its foreground terminal group.

| State / signal | Delivery and status |
|---|---|
| Foreground terminal group; INT, HUP, TERM | No forwarding; a group signal already reaches the engine. A signal to scode's PID alone does not reach it. One warning per run explains this. Engine's eventual status is retained. |
| No controlling terminal or background group; INT, HUP, TERM | Forwarded to the engine PID. A group-directed signal can arrive twice, once directly and once forwarded. Engine's eventual status is retained. |
| Terminal classification unavailable | Falls back to forwarding |
| INT queued before launch | Pending marker is read after signal restoration; engine can be prevented from launching, with status 130 |
| TERM/HUP queued before launch | Delivered after the engine PID becomes available |
| QUIT | Not forwarded. scode exits 131 and runs accounting/cleanup. A terminal-group QUIT can kill the engine directly; PID-only QUIT can leave it alive. |
| KILL | No trap, accounting, or cleanup guarantee |

For fatal engine signals, the conventional statuses are INT 130, HUP 129,
TERM 143, and QUIT 131. An engine that handles a signal can choose another
status. Logging failure and scode's own QUIT handling are exceptions to
preserving that status.

The launcher uses system Python, then system Perl, to restore SIGINT,
SIGQUIT, SIGPIPE, and SIGXFSZ dispositions before exec. Without both
interpreters it warns and preserves inherited ignored dispositions, including
loss of a queued launch-window INT. SIGPIPE normally gives 141 for a
terminated output pipeline.

A separate engine process group with terminal ownership and stopped-child
handling would resolve the PID/group ambiguity. That is a deferred process
control redesign, not a guarantee of the current implementation.
