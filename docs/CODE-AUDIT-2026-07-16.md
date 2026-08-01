# Code and security audit — 2026-07-16

## Executive summary

The repository was reviewed file by file across the Bash runtime, Node preload,
tests, examples, packaging, CI, release documentation, and repository-local
configuration. The review found no critical issue, nine high-severity issues,
fourteen medium-severity issues, and six low-severity issues or weaknesses.

All correctness and security defects that can be fixed safely in this working
tree were fixed and regression-tested. Three high-severity supply-chain or local
operator findings remain open because they require owner action outside the
runtime code. Two platform/design limitations remain documented and need an
explicit product decision.

The final local gate is green:

- 101 Node tests and 505 Bats tests pass (606 total).
- Shell line coverage is 83.97% (1,524/1,815).
- Node statements/lines are 86.13%, branches 84.60%, and functions 100%.
- Bash syntax, ShellCheck, Node syntax, Ruby syntax, JSON parsing, packaging,
  and whitespace checks pass.
- `npm audit` reports zero known vulnerabilities. `npm outdated` reports no
  outdated direct dependency.

This is not a claim that the product is a perfect containment boundary. The
open findings and platform limits below are material.

## Scope and mental model

`scode` is a policy-composition and process-launch wrapper. It reads user and
project configuration, resolves a project and command, composes default,
platform, user, project, and CLI allow/block rules, scrubs environment values,
then emits and executes either a macOS SBPL policy through `sandbox-exec` or a
Linux mount/network namespace policy through `bubblewrap`. Optional audit
logging streams sandbox stderr to a protected log descriptor. The Node preload
patches `child_process` calls so Chromium receives `--no-sandbox` when it is
nested inside the outer OS sandbox.

The security-sensitive flows are therefore:

1. untrusted CLI/config/path input into canonical policy records;
2. policy precedence into SBPL rules or ordered bubblewrap mounts;
3. ambient host authority into child descriptors, environment, sockets, and
   namespace binds;
4. requested command text into exact executable resolution and Node shell
   rewriting;
5. audit data into terminal and log output;
6. source/release material into installation and CI.

Reviewed repository files:

- runtime and preload: `scode`, `lib/no-sandbox.js`;
- build/package: `Makefile`, `Formula/scode.rb`, `package.json`,
  `package-lock.json`, `LICENSE`, `.gitignore`;
- CI/security: `.github/workflows/ci.yml`, `.github/SECURITY.md`, and the local
  `.claude/settings.local.json`;
- tests: every file under `test/`;
- documentation: `README.md`, `CHANGELOG.md`, all files under `docs/`;
- examples: every file under `examples/`.

Generated coverage data and a literal `~/.local` install tree left by the old
unexpanded-prefix behavior were inspected as artifacts and moved to Trash.

## Critical findings

None found.

## High findings

### H-01 — Linux mount order could reopen blocked paths or a read-only project — fixed

- **Where:** `scode`, `build_bwrap_args`, `build_bwrap_args_strict`, and the new
  `append_bwrap_final_policy` function around line 2,412.
- **What:** bubblewrap applies mounts in order. Project, preload, or allow binds
  could appear after a deny mask and expose the path again. An allowed ancestor
  could also make a read-only project writable.
- **Why:** the rendered command looked restrictive while the effective final
  mount tree was less restrictive. This could expose credentials or permit
  project mutation.
- **Fix:** policy rendering now has a final authoritative phase: custom and
  mandatory blocks are reasserted after internal/project binds, only explicit
  child exceptions are reopened, and the project is finally rebound read-only
  when requested. Exact-order and runtime regression tests cover the cases.

### H-02 — Grok mandatory containment was not invariant — fixed

- **Where:** `scode`, Grok policy composition around lines 3,078–3,365.
- **What:** mandatory `.git`, `.grok`, dotenv, and collection controls were
  mixed into ordinary policy arrays. A later allow could overlap and reopen
  them.
- **Why:** a profile named as a defense could silently lose the properties it
  promised.
- **Fix:** mandatory defense blocks have an explicit `defense` source, are
  appended authoritatively, reject every overlapping allow, and reject a block
  that would cover the project root. Tests exercise both CLI and configuration
  conflicts.

### H-03 — `--no-net` left ambient local authority channels — fixed with documented limit

- **Where:** `scode` startup, environment composition, and Linux builders around
  lines 13–16, 2,484–2,495, 3,286–3,296, and 3,465.
- **What:** `SSH_AUTH_SOCK` could remain usable, and Linux could bind
  `XDG_RUNTIME_DIR` even when a new network namespace was requested.
- **Why:** Unix-domain sockets can carry authentication or service authority
  without ordinary IP connectivity. Calling this state “no network” would be
  misleading.
- **Fix:** SSH agent variables are removed from the ambient child environment;
  a discovered agent socket is blocked by default and requires both an exact
  `--allow` and an explicit child `SSH_AUTH_SOCK`. Linux no-network mode no
  longer binds or exports `XDG_RUNTIME_DIR`. A live agent-connection regression
  test verifies the double opt-in.
- **Limit:** standard streams and deliberately allowed sockets are still
  authority channels; this is stated in the README and hardening document.

### H-04 — macOS strict mode could block its own project and command — fixed

- **Where:** `scode`, macOS strict profile construction around lines
  2,080–2,330 and final command auto-allow composition.
- **What:** a project below a default-blocked parent and an executable installed
  outside system prefixes could remain denied after strict policy generation.
- **Why:** valid strict sessions failed at runtime, encouraging users to weaken
  the profile or abandon strict mode.
- **Fix:** redundant parent blocks are omitted in strict mode and the exact
  canonical project and executable are added at the correct final precedence.
  Runtime tests cover a project under a built-in blocked parent and a user-local
  command.

### H-05 — macOS inherited descriptors and shared temporary access crossed the boundary — fixed

- **Where:** `scode`, `run_macos_sandbox_engine` around lines 754–769 and macOS
  profile/run setup around lines 3,630–3,740.
- **What:** arbitrary caller file descriptors were inherited by the sandbox;
  the profile allowed shared temporary locations broadly; signal permission was
  broader than necessary.
- **Why:** open descriptors bypass path policy, while shared temporary access
  creates cross-process read/write channels.
- **Fix:** the fixed privileged Bash launcher closes every descriptor above 2
  before replacing itself with `sandbox-exec`; each run receives a private
  temporary directory; shared `/tmp` paths are denied; broad signal permission
  was removed. Production tests verify descriptor closure and private-temp
  behavior.
- **Limit:** broad Mach lookup remains necessary for supported harness/runtime
  compatibility; see O-04.

### H-06 — shell command rewriting could corrupt or misclassify commands — fixed

- **Where:** `lib/no-sandbox.js`, lexer and injection functions around lines
  71–954.
- **What:** the former regular-expression tokenizer mishandled nested quoting,
  adjacent quoted/unquoted fragments, escaped separators, comments, absolute
  wrapper paths, `time` options, and flow-control keywords.
- **Why:** a preload must not change program meaning. Corruption could execute a
  different command; missed detection could make Chromium fail inside the
  outer sandbox.
- **Fix:** a stateful quote/escape/comment-aware lexer records exact spans;
  rewriting is span-based and quote-aware; wrapper-specific parsing was added;
  absolute wrappers are recognized by basename; unsupported substitutions and
  heredocs are preserved unchanged. Syntax and real-process tests cover these
  branches.

### H-07 — source installation lacked immutable verification — mitigated; release signing open

- **Where:** `README.md` source/manual install sections and Git tags/releases.
- **What:** installation instructions could follow mutable repository state or
  fetch files without cryptographic verification. Existing release tags are
  lightweight and unsigned.
- **Why:** compromise or mutation of the source endpoint could become direct
  code execution during installation.
- **Fix:** the documented source install checks out exact commit
  `467b53761236d8647428ab73d7246f86426d38bb`; manual downloads pin that commit
  and verify SHA-256 for `scode`, `no-sandbox.js`, and `LICENSE` before install.
- **Open:** publish signed annotated tags/releases and signed checksum or
  provenance assets. Existing public tags cannot be retroactively made
  trustworthy without an owner-controlled release process; see O-01.

### H-08 — local Claude permissions authorize broad and destructive commands — open

- **Where:** `.claude/settings.local.json`, especially lines 4, 15, 26, 37, and
  42.
- **What:** the local file grants `Bash(python3:*)`, ordinary pushes, force
  pushes, force tag updates, and release operations without per-command review.
- **Why:** a prompt/tool compromise can turn those grants into arbitrary local
  execution or destructive remote repository mutation.
- **Fix applied:** the exact local filename is ignored so it cannot be committed
  accidentally.
- **Owner action:** reduce grants to narrow non-destructive commands and require
  interactive approval for push, force, tag, and release operations. The audit
  did not edit user-local permissions without authorization.

### H-09 — the public repository has no active remote CI or protection controls — open

- **Where:** `bindsch/scode` GitHub repository settings as queried on
  2026-07-16.
- **What:** the remote reports zero Actions workflows, an unprotected `main`,
  and disabled Dependabot security updates, secret scanning, and push
  protection.
- **Why:** local gates do not protect the public branch or release path until
  the workflow is committed and required; secrets and dependency advisories
  receive no platform-side guard.
- **Fix prepared:** `.github/workflows/ci.yml` tests macOS/Linux on Node
  22/24/26, runs audit and coverage, and disables checkout credential
  persistence.
- **Owner action:** review/commit the workflow, require its checks on `main`,
  require reviewed pull requests, restrict force pushes/tag mutation, and
  enable the available security features. No remote setting was changed.

## Medium findings

### M-01 — project config was vulnerable to link/race/size abuse — fixed

- **Where:** `scode`, project `.scode.yaml` loading around lines 3,005–3,036.
- **What:** a project-controlled symlink or changed file could redirect parsing;
  hard links weakened ownership assumptions; no size ceiling bounded parsing.
- **Why:** an untrusted project could substitute policy during validation or
  cause excessive resource use.
- **Fix:** reject symlinks and multi-link/non-regular/non-owned files, enforce a
  1 MiB limit, open once on descriptor 8, compare path and descriptor identity,
  and parse the stable descriptor. Symlink, hard-link, and oversize tests were
  added.

### M-02 — command lookup had a PATH time-of-check/time-of-use window — fixed

- **Where:** `scode`, command resolution and final launch.
- **What:** the command could be inspected from one PATH state and executed by
  name from another.
- **Why:** a concurrently replaced PATH entry could execute a binary that was
  not the one used to compose the sandbox policy.
- **Fix:** non-dry execution uses the canonical executable path that was
  validated. Logs retain the requested argv separately so audit records remain
  faithful.

### M-03 — internal preload mounting could override an explicit block — fixed

- **Where:** `scode`, Linux preload bind and final policy rendering.
- **What:** binding the preload library or its containing directory after user
  blocks could reopen blocked content.
- **Why:** internal implementation details must not weaken explicit policy.
- **Fix:** only the exact preload file is mounted, and an overlapping explicit
  block disables preload injection with a warning instead of reopening policy.

### M-04 — file, socket, FIFO, and symlink blocks used directory semantics — fixed

- **Where:** `scode`, `append_bwrap_block` around lines 2,380–2,395.
- **What:** non-directory nodes could receive a `tmpfs`-style mask or be handled
  inconsistently.
- **Why:** the generated mount could fail or leave the original node usable.
- **Fix:** directories use `tmpfs`; every existing non-directory node uses an
  inert `/dev/null` read-only bind. Tests cover files, FIFOs, and symlinks.

### M-05 — logging accepted unsafe destinations and could silently be incomplete — fixed

- **Where:** `scode`, output-path resolution, `write_log_header_json`, and
  `run_with_stderr_log` around lines 684–751.
- **What:** an existing directory could be accepted as a log destination;
  replacement races and writer failures could redirect or truncate audit data.
- **Why:** a security audit log must fail closed rather than imply a complete
  record when writes fail.
- **Fix:** directory destinations are rejected; the log is created through a
  private inode at mode 0600 and retained on descriptor 9; the writer is waited
  and a failed writer makes the command fail. Tests cover symlink replacement,
  directory rejection, permissions, and signal behavior.

### M-06 — wrapper-wide `--no-sandbox` caused a false negative — fixed

- **Where:** `lib/no-sandbox.js`, command-tail scanning and `patchWrapperArgs`.
- **What:** a `--no-sandbox` token belonging to a wrapper or earlier argument
  could suppress insertion for the actual Chromium child.
- **Why:** Chromium would launch without the compatibility flag and fail under
  the outer sandbox.
- **Fix:** only the actual Chromium argument tail is inspected; nested wrapper
  parsing stops at the resolved command. Regression tests cover false-positive
  wrapper flags.

### M-07 — inherited `NODE_OPTIONS` could load before the security preload — fixed

- **Where:** `scode`, environment export around line 3,565.
- **What:** the scode preload was appended after inherited Node options.
- **Why:** earlier preload code could capture unpatched APIs or interfere before
  scode installed its wrappers.
- **Fix:** scode's exact `--require=` entry is prepended while preserving the
  caller's options.

### M-08 — audit and terminal records accepted ambiguous/control-bearing data — fixed

- **Where:** `scode`, path validation, message output, JSON/legacy log headers,
  and audit categorization around lines 1,150–1,173 and 1,800–1,875.
- **What:** terminal control characters could affect diagnostics, and `|` as an
  internal record delimiter collided with valid path characters.
- **Why:** diagnostics could be visually spoofed and path categories could be
  parsed incorrectly.
- **Fix:** all policy/output paths reject control characters; messages escape
  controls defensively; audit records use ASCII unit separator after validation;
  JSON retains exact argv boundaries. Tests cover C0 characters, colons, pipes,
  quotes, spaces, and terminal controls.

### M-09 — the macOS profile granted broad signal authority — fixed

- **Where:** `scode`, generated strict/default SBPL profiles.
- **What:** `(allow signal)` was granted without target restriction.
- **Why:** the child could signal unrelated same-user processes.
- **Fix:** the blanket grant was removed. Required termination is handled by the
  parent wrapper and tested.

### M-10 — install/uninstall could target the filesystem root and omitted the license — fixed

- **Where:** `Makefile` lines 16–39 and `Formula/scode.rb` lines 16–29.
- **What:** `PREFIX=/` allowed dangerous writes/removals; an unexpanded `~`
  created a literal repository-local tree; installed packages omitted LICENSE.
- **Why:** a typo could mutate system paths and packages were incomplete.
- **Fix:** unsafe/empty/unexpanded prefixes fail before mutation, LICENSE is
  installed/uninstalled and included in the formula, and packaging tests verify
  all artifacts.

### M-11 — CI runtime/security defaults were stale or incomplete — fixed locally

- **Where:** `package.json` and `.github/workflows/ci.yml`.
- **What:** supported Node versions and CI did not cover the active even-numbered
  release set; checkout credentials remained available to later steps.
- **Why:** untested runtimes accumulate compatibility defects and retained CI
  credentials increase workflow blast radius.
- **Fix:** engines and matrix cover Node 22, 24, and 26; checkout uses
  `persist-credentials: false`; audit and coverage are explicit jobs.
- **Limit:** the workflow is not active until committed and enabled remotely.

### M-12 — tests contained false positives and missed security branches — fixed

- **Where:** existing Bats and Node suites under `test/`.
- **What:** several negative tests accepted broad substrings or did not assert
  the exact effective output; configuration tests could inherit host state;
  link/socket/mount-order/descriptor/failure paths were missing.
- **Why:** broken behavior could still produce a green suite.
- **Fix:** assertions now compare exact output where material; fixtures isolate
  configuration; 23 regression tests cover the bugs above, including live
  subprocess, descriptor, socket, and filesystem behavior.

### M-13 — security documentation overstated isolation — fixed

- **Where:** `README.md` and examples, particularly Grok and cloud profiles.
- **What:** no-network/no-exfiltration language was stronger than the actual OS
  mechanisms, and examples opened complete cloud credential directories without
  emphasizing the consequence.
- **Why:** operators could make decisions based on a guarantee the software
  cannot provide.
- **Fix:** the documentation distinguishes IP namespace isolation from local
  streams/sockets, states the macOS/bubblewrap limits, removes performance claims
  not supported by a benchmark, and warns that full credential-directory allows
  expose every credential in that directory.

### M-14 — no coordinated vulnerability disclosure path existed — fixed locally

- **Where:** repository documentation.
- **What:** reporters had no private security contact or response expectations.
- **Why:** vulnerabilities were more likely to be disclosed publicly or lost.
- **Fix:** `.github/SECURITY.md` documents the owner security contact, supported
  version, report contents, and disclosure expectations.

## Low findings

### L-01 — duplicated/dead JavaScript parsing helpers increased drift risk — fixed

- **Where:** `lib/no-sandbox.js`.
- **What:** obsolete command-token and Chromium-string helpers duplicated active
  parsing logic.
- **Why:** two implementations of shell semantics inevitably diverge.
- **Fix:** dead helpers were removed and active pure helpers are exported only
  under `SCODE_TEST=1`.

### L-02 — the preload double-load guard was string-keyed global state — fixed

- **Where:** `lib/no-sandbox.js` around line 982.
- **What:** an ordinary global property name could collide with application code.
- **Why:** collision could suppress patch installation or overwrite app state.
- **Fix:** the guard uses `Symbol.for('dev.scode.no-sandbox.loaded.v1')`.

### L-03 — Homebrew tests asserted too little — fixed

- **Where:** `Formula/scode.rb` test block.
- **What:** tests could pass without checking all installed artifacts or useful
  command behavior.
- **Why:** a broken formula could be published after a superficial test.
- **Fix:** tests assert the executable, preload, LICENSE, every example including
  Grok, help output, dry-run behavior, and audit parsing.

### L-04 — release gates omitted dependency and signing checks — fixed locally

- **Where:** `docs/RELEASE-GATE.md`.
- **What:** the checklist did not require audit, immutable source verification,
  LICENSE packaging, or signed release review.
- **Why:** manual releases could bypass the controls added to code/CI.
- **Fix:** the checklist now includes coverage, `npm audit`, package contents,
  commit/checksum verification, signing, and repository security controls.

### L-05 — generated artifacts were not consistently ignored — fixed

- **Where:** `.gitignore`.
- **What:** local coverage output and user-local agent permission state could
  appear in repository status or be committed accidentally.
- **Why:** generated noise obscures real changes; local approval rules disclose
  operator behavior and can transfer unsafe permissions.
- **Fix:** ignore `coverage/` and `.claude/settings.local.json`.

### L-06 — security-critical files remain oversized — open architectural debt

- **Where:** `scode` (about 3,800 lines) and `lib/no-sandbox.js` (about 1,400
  lines).
- **What:** policy parsing, rendering, execution, logging, and audit behavior are
  concentrated in large files.
- **Why:** review cost and regression risk rise as unrelated concerns share
  mutable global state.
- **Recommendation:** after this release, split pure path/config composition,
  platform renderers, execution/logging, and audit parsing behind stable tests.
  Do not combine that refactor with security-policy changes.

## Coverage before and after

| Metric | Before | After | Gate |
|---|---:|---:|---:|
| Tests | 92 Node + 491 Bats = 583 | 101 Node + 505 Bats = 606 | all pass |
| Bash lines | 84.27% (1,430/1,697) | 83.97% (1,524/1,815) | >=80% |
| Node statements | 84.89% | 86.13% | >=80% |
| Node lines | 84.89% | 86.13% | >=80% |
| Node branches | 83.46% | 84.60% | >=80% |
| Node functions | 96.00% | 100.00% | >=80% |

The Bash percentage fell by 0.30 points because the fixes added more executable
branches than covered lines, while absolute covered lines increased by 94. The
gate excludes 205 declarative lines between
`SCODE_COVERAGE_STATIC_START/END`: Bash's DEBUG trap cannot attribute individual
multi-line array entries. These are static policy tables, not executable
branches, and generated-policy/environment tests exercise their effects. The
exclusion is visible in `test/kcov-scode-wrapper.bash`; it is not a hidden
post-processing adjustment.

On the macOS audit host, Linux bubblewrap runtime tests and the unavailable
`ionice` integration are skipped; Linux command construction is still tested.
The normal `make test` run verifies nonstandard descriptor closure. Coverage
instrumentation skips that one test because kcov requires its own descriptor,
and skips long-running signal/watch tests that kcov intercepts; the production
suite runs those paths.

## Final verification evidence

- `make test`: pass, 101 Node + 505 Bats.
- `make coverage`: pass, all shell and Node dimensions above 80%.
- `bash -n scode`: pass.
- `shellcheck -x scode`: pass.
- `node --check lib/no-sandbox.js`: pass.
- `ruby -c Formula/scode.rb`: `Syntax OK`.
- `package.json` and `package-lock.json`: parse successfully.
- `npm audit --json`: 0 info/low/moderate/high/critical vulnerabilities.
- `npm outdated --json`: empty result.
- `git diff --check`: pass.
- install/uninstall packaging: pass in an isolated prefix; unsafe root and
  unexpanded-tilde prefixes fail before mutation.

## Open items and owner decisions

### O-01 — release authenticity and provenance — high

Choose and enforce a release identity. Recommended: signed annotated Git tags,
signed checksum/provenance assets attached to each GitHub release, and a Homebrew
formula pinned to the verified archive digest. Do not force-rewrite existing
public tags as a substitute for a documented trust transition.

### O-02 — local agent permission grants — high

Decide whether to replace `.claude/settings.local.json` with a minimal allowlist.
Recommended: remove `python3:*`, force-push, force-tag, amend, and release grants;
approve them interactively only when deliberately requested.

### O-03 — GitHub repository controls — high

Commit/review the prepared CI workflow, then enable branch protection, required
checks/reviews, tag protection, Dependabot security updates, secret scanning,
and push protection. These are external mutations and were not performed by the
audit.

### O-04 — deprecated macOS sandbox interface and broad Mach lookup — medium/high residual

The generic macOS backend still depends on deprecated `sandbox-exec`, imports
Apple's private `system.sb`, and allows broad Mach lookup for compatibility.
There is no reliable generic service allowlist for all supported harnesses. For
a stronger boundary, require a dedicated VM or containerized Linux environment,
or build a separately entitled macOS helper with an explicit service model.

### O-05 — unsupported shell grammar policy — medium product decision

The Node preload deliberately preserves command substitutions, backticks, and
heredocs rather than partially rewriting them. This avoids command corruption
but may leave Chromium without the compatibility flag. Decide whether a future
major version should fail closed on those forms or adopt a real shell AST
parser. Adding a parser is a dependency/security decision and should not be done
silently.

### O-06 — structural decomposition — low

Plan a test-preserving split of the two oversized security-critical files after
the current policy behavior is released and stable.

## Further hardening recommendations

1. Add a Linux privileged CI runner or scheduled VM job that executes the real
   bubblewrap runtime tests, including no-network and Unix-socket cases.
2. Add release provenance (for example, GitHub artifact attestations) and verify
   it in the Homebrew update process.
3. Add mutation testing for policy precedence and the JavaScript lexer; coverage
   alone cannot prove assertions detect semantic inversions.
4. Fuzz config scalar/list parsing, audit denial parsing, and shell tokenization
   with bounded inputs and corpus regression storage.
5. Add an explicit capability report to `--dry-run` listing inherited standard
   streams, allowed sockets, network namespace state, and residual macOS Mach
   authority.
6. Re-run this audit after any change to policy ordering, sandbox backends,
   command parsing, or release/install instructions.

## External references used for boundary decisions

- Bubblewrap describes itself as a low-level tool for constructing sandbox
  environments and explicitly leaves the security policy to its caller:
  <https://github.com/containers/bubblewrap>.
- Linux network namespaces isolate network devices, protocol stacks, routing,
  firewall rules, and Unix abstract socket namespace:
  <https://www.man7.org/linux/man-pages/man7/network_namespaces.7.html>.
- Filesystem Unix-domain sockets remain pathname-based IPC objects:
  <https://man7.org/linux/man-pages/man7/unix.7.html>.
- Maintained Node release status informed the 22/24/26 matrix:
  <https://nodejs.org/en/about/previous-releases>.
- GitHub's checkout action documents credential persistence and its opt-out:
  <https://github.com/actions/checkout>.
- GitHub's secure-use guidance informed branch, token, review, and workflow
  recommendations:
  <https://docs.github.com/en/actions/reference/security/secure-use>.
