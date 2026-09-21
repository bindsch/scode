# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Per-run scratch usage accounting (opt-in).** Setting `SCODE_ACCOUNT_FILE`
  to a writable file makes scode append one JSON line at exit describing the
  private scratch directory it created and tore down: `scratch_kib` measured
  just before teardown, run duration, exit code, and an optional correlation
  token from `SCODE_ACCOUNT_ID`. The line is the measurement hook for
  workspace-storage studies — and for any fleet operator who wants to know
  what sandboxed runs actually leave behind. Every invocation past argument
  validation records — failed launches included; `--help`, `--version`, and
  `audit` do not.
  A relative account path resolves against the invoking directory; the parent
  directory must exist; the id accepts letters, digits, and `. _ : -`, capped
  at 128 characters (a longer id is dropped, never truncated). Each record is
  a single append bounded at 800 bytes — a path that would not fit nulls
  itself, a record that still exceeds the bound is dropped with a warning —
  so concurrent runs sharing one sink interleave whole lines instead of
  corrupting them. The sink is opened once when accounting is armed —
  created then if it does not exist yet — and the record travels through
  that descriptor, so a path swapped during the run cannot redirect the
  append; a replaced sink drops the record with a warning.
  A failed append — a full disk, a file-size limit — is
  reported on stderr and sealed with a best-effort newline, so a partial
  record cannot swallow the next run's line; the run's own exit status
  and teardown are never touched.
  The warning itself cannot take the run down: the exit trap ignores
  SIGPIPE for its own writes, so a stderr reader that has already exited
  cannot turn the diagnostic into a signal death that replaces the run's
  status and skips the teardown (mid-run writes keep the conventional
  disposition).
  The
  variables are consumed into private state and unset before the sandboxed
  command runs, so the child does not learn them through its environment —
  confidentiality, not integrity: keep the sink outside the sandbox's
  writable area. On Linux the `/tmp` tmpfs lives only inside the bwrap
  namespace, so any run that reached the launch stage records
  `scratch_kib: null` with `reason: "tmpfs_unmeasurable"` — whether the
  namespace actually formed is not observable from outside; a run that
  never attempted a launch (dry-run — and on Linux engine-not-found too)
  records `reason: "no_scratch"` instead — the label describes what
  happened, not a guess. On macOS an engine-not-found run has already
  created the private scratch directory by the time the engine check
  fails, so that case records the directory with `scratch_kib: 0`.

### Fixed

- **Scratch teardown could silently leave the whole directory behind.** The
  sandboxed command controls its scratch dir, so it could create a directory
  locked against itself (mode 000); `rm -rf` cannot descend into such a
  directory to enumerate it, gave up, and the entire scratch directory
  survived teardown with no warning. Teardown now grants the owner the
  minimum needed — on directories only, since unlink never needs file modes
  and a linked file's mode is shared with any outside copy — and retries a
  bounded number of times, so nested locks are also uncovered. Found by the
  accounting tests: the new EXIT-trap ordering made the leftover state
  observable.
- **A run terminated by a signal recorded the wrong exit code.** A fatal
  signal kills bash while `$?` still holds the last command's status, so the
  EXIT-trap record could say `exit_code: 0` for a run the caller saw die
  with SIGTERM. Top-level INT/TERM/HUP/QUIT handlers now exit with the
  conventional codes (130/143/129/131), which the record then carries — and
  both engine paths now stop promptly: the sandbox engine runs as a child
  with forwarding handlers whether or not `--log` was passed, since bash
  defers traps while a foreground command runs, and each runner restores
  the conventional handlers instead of clearing them when it returns.
- **The --log path kept neither stdin nor the engine alive under a
  forwarded signal.** Backgrounding the engine for prompt forwarding has two
  async-child costs in bash: stdin defaults to `/dev/null` (piped input
  vanished; interactive harnesses saw a dead stdin), and a signal sent to
  the backgrounded shell killed that shell only, orphaning the engine
  behind it. The backgrounded launch now carries an explicit `<&0`, and the
  engine launcher ends in `exec`, so `$!` is the engine process itself and
  the forwarded signal reaches it directly.
- **Sandboxed commands ignored Ctrl-C and Ctrl-\\ entirely.** Bash applies
  SIG_IGN to SIGINT and SIGQUIT in an asynchronous child when job control is
  off, and the ignored disposition survives every exec in the launch chain —
  so `sleep`, `make`, or any command without its own handler ignored both
  the forwarded signal and the terminal's group signal, while scode
  waited for it to finish. The launcher now restores SIG_DFL for both
  signals through `/usr/bin/python3 -I` before the final exec (isolated
  mode, so the project directory and inherited `PYTHON*` variables cannot
  reach the interpreter). The macOS secret-handling path already required
  `/usr/bin/python3`; Linux hosts usually ship it too. Where it is
  missing, the chain retries the same restore and the same pending-INT
  read with `/usr/bin/perl` (present on macOS and nearly every Linux
  host; the absolute path keeps a project-supplied perl from running
  before the sandbox starts). Only on a host with neither interpreter
  does the chain warn on stderr, keep the old, broken dispositions, and
  skip the pending-INT read. The chain also moves `PERL5OPT`, `PERL5LIB`,
  `PERLLIB`, and `PERL5DB` to carrier names for the interpreter's startup
  — an inherited `PERL5OPT` could otherwise load a module from the project
  before the sandbox starts — and restores them before the exec, keeping
  an empty value distinct from an unset one, so the engine still sees the
  environment the caller supplied, intact.
  On macOS `/usr/bin/python3` is a shim that resolves the real interpreter
  through `xcrun` and honors `DEVELOPER_DIR` before any python code runs,
  so `-I` cannot stop a pointed-at developer directory from executing code
  ahead of the sandbox; the chain moves `DEVELOPER_DIR` aside for the shim
  and restores it for the engine, keeping the caller's value intact. The launcher also restores SIGPIPE and SIGXFSZ, which
  CPython itself ignores at startup — without that, a truncated pipeline
  (`yes | head`) exited 1 with a write error instead of the conventional
  141.
- **A Ctrl-C at the terminal is delivered to the engine exactly once, and
  the engine's own status always stands.** INT and HUP are generated for
  the whole foreground process group, and the engine is a child in scode's
  group — required for its interactive stdin — so a terminal-generated
  signal already reached the engine. No interface tells a trap whether the
  signal was generated for the group or aimed at scode's pid alone, and
  both guesses fail: forwarding a second copy interrupted engines that
  were still handling the first signal (a CLI whose first ^C means
  "interrupt the current work and keep running" received a second ^C and
  quit), while forwarding nothing silently swallowed signals aimed at
  scode's pid. scode now treats every INT/HUP as a terminal-group signal:
  one delivery, the engine's exit status stands (the conventional `128+n`
  when it dies by the signal, its own code when it handles one — the
  interrupted wait's status is recovered from bash, which retains a reaped
  child's status), and a signal aimed at scode's pid while scode holds the
  terminal's foreground group is not forwarded. Because the two cases
  cannot be told apart, the first such signal in a run prints a one-line
  stderr note that nothing is being forwarded: information for a
  supervisor that pid-signaled scode, expected noise for a terminal ^C. The
  structural fix — giving the engine its own process group and making it
  the terminal's foreground group, so each signal source has exactly one
  target — is planned but deferred: a stopped engine would become
  unreportable, since bash `wait` never returns stopped children. TERM
  joins the same classification when the engine shares the foreground
  group: a supervisor signaling the whole group has already delivered it,
  so no second copy is forwarded. When scode holds no terminal or sits in
  a background group, every signal -- TERM included -- is forwarded,
  because the terminal does not generate TERM there; if `ps` cannot
  classify a signal, the traps fall back to a plain forward. The cost of
  forwarding without terminal truth: a stop aimed at scode's whole group
  reaches the engine twice there -- the group delivery, then the
  forwarded copy; the deferred group rewrite is the structural fix.
- **A signal queued before the engine's launch is no longer lost.** The
  fresh launcher chain keeps SIGINT ignored from the async fork until its
  python restores SIG_DFL, so delivering a queued INT right after the fork
  landed in that ignored window and was discarded — the engine then ran to
  completion as if no signal had arrived. Worse, an INT that arrived
  between the fork and scode's recording of the engine pid was queued only
  in scode's own process, which the already-forked launcher never sees.
  INT is now recorded in a per-run pending file the launcher reads once
  the restore is done — shared state, so it covers both windows, on the
  `--log` path and off it — the engine never launches, and the run exits
  with the conventional 130. The record is backed by a kill at flush
  time, so an INT whose record the launcher has already passed still
  reaches the live engine, and the trap-time append rides a descriptor
  pinned at creation, so a swapped path in a command-writable temp
  directory cannot redirect it, and scode closes fd 7 at startup, so a
  descriptor the caller happened to hold open there cannot receive the
  record when creation fails — the write fails silently, as documented.
  Queued TERM and HUP are delivered right
  after the launch as before (their dispositions are default in the
  child from the start). The trap-referenced state starts every run
  empty, so an inherited environment cannot aim the pending-file
  cleanup at an unrelated file or forge an armed accounting flag, and
  an interrupted wait now recovers the engine's own status even when
  the forward missed a child that had already exited. A Ctrl-C that
  lands while the trap is still classifying cannot slip past the
    launcher's read anymore: the trap holds a per-run mark directory in
  place while it works, and the launcher waits (bounded) for the mark
  to
  disappear before it reads the pending file, so a record being
  written
  right now is never read as an empty file. The mark is a
  directory, not a
  written file, because mkdir and rmdir refuse to
  follow a symlink planted
  at the mark path. On the `--log` path the writer outlives the engine -- an engine that
  survives a forwarded signal keeps logging, instead of losing its
  remaining stderr to a broken pipe -- and scode ends it only after a
  sentinel line it appends last has shown up in the log, which proves the
  engine's stderr was drained. The writer mirrors the logging pipe to
  scode's stderr, so the sentinel line also appears there once per run.
  The sentinel gives the log a visible `scode-log-complete run
  <pid>-<token>` final line, with a token drawn from the OS randomness
  source each run and unguessable from inside the sandbox — a host that
  cannot read the OS randomness source falls back to a weaker
  shell-random token — so a command cannot forge its own
  completion marker. Once the writer has ended, output that a daemonized
  grandchild writes after the engine has been reaped is not waited for
  and can be lost. A writer death is suppressed only when the run killed
  it after that proof -- scode then warns that the stderr mirror may be
  missing the tail the writer was still flushing -- or when a
  terminal-group signal reached the writer
  through the group and the sentinel arrived anyway; any other writer
  death -- an internal failure, an outside kill, or a run that had to end
  a wedged writer before the sentinel showed -- is reported and turns the
  status nonzero.
- **The accounting sink is refused when it is not a plain regular file.** A
  FIFO with no reader blocked the exit forever; a symlink would have made
  scode append through the link with full privileges. Both are rejected at
  arm time with a warning, and the write re-validates the sink against
  the file the arm-time descriptor holds, so a sink that stopped being a
  regular file drops its record with a warning instead of being appended
  through. The directories on the
  sink's path are fingerprinted at arm time and re-verified at the write:
  a command that swaps a parent (a project `logs/` directory, say) for a
  symlink aimed outside the sandbox cannot aim the append outside anymore.
  The fingerprint follows links: an ancestor that already is a symlink is
  tracked by the directory it points at, so swapping that target mid-run
  drops the record the same way.
  Bash has no O_NOFOLLOW, so the guarantee is this re-validation — which
  runs after the sandbox has exited, when the racing writer is gone — not
  race immunity; sinks inside the child-writable area remain discouraged at
  arm time.
- **A caller file-size limit can no longer kill scode through its own
  accounting append.** Under `ulimit -f 0`, the first write past the limit
  raises SIGXFSZ, whose default action terminates the shell — the
  EXIT-trap append included, skipping the scratch teardown and replacing
  the run's status. scode ignores SIGXFSZ in its own shell, so a refused
  write fails like any other failed write (warned, record dropped,
  teardown intact); the launch chain still restores the default
  disposition for the engine, whose pipelines keep the conventional 141.

## [0.4.0] - 2026-09-15

### Added

- **Sandboxed `claude` authenticates on macOS.** Claude Code keeps its
  subscription credential in the Keychain, which the sandbox blocks along with
  the rest of `~/Library`, so a sandboxed `claude` reported `Not logged in`
  against a valid session. Before exec, scode now copies the credential from
  the Keychain to `~/.claude/.credentials.json`, the file store Claude Code
  also reads, inside the directory the harness auto-allow already covers. The
  copy is made from the parent process, which is still outside the sandbox,
  and remade on every launch: a token refresh migrates the credential back to
  the Keychain and empties the file, so a copy made once does not hold. The
  copy never replaces a credential that expires later than the Keychain's,
  since a refresh inside the sandbox writes the file but cannot write the
  Keychain, and the provider invalidates the old refresh token on rotation.
  It is skipped wherever the sandbox could not use it, because there it would
  only cost secrecy: under `--dry-run`, under `--trust untrusted`, when
  `--block` puts `~/.claude` or the credential file out of reach, behind a
  wrapper such as `env` whose final binary cannot be checked, for a `claude`
  binary inside the project, and when `~/.claude` resolves into the project
  through a redirected `HOME` or a symlink. `--no-credential-sync` declines
  the copy; sandboxed `claude` then cannot authenticate. Trade-off, stated in
  the README: the refresh token rests in a file the sandboxed agent can read,
  the exposure every other harness's state directory already has.

### Changed

- The help text and README now say that strict mode's harness auto-allow is
  read-write, which it has been since 0.3.4.

## [0.3.4] - 2026-08-15

### Fixed

- **Strict mode permanently destroyed OAuth logins.** The harness state
  auto-allow was read-only, which does not prevent a token exchange, only the
  recording of its result: the harness reads a valid refresh token, the
  provider rotates and invalidates it, and the replacement cannot be written
  back. One strict-mode run was therefore enough to break `codex login` for
  good, with no error at the time it happened, reported later as
  `refresh_token_reused`. Harness state directories are now bound read-write on
  both platforms. The grant stays confined to the harness's own directory;
  unrelated credential stores remain blocked.
- Harness detection now ignores a trailing `.exe` on the resolved binary.
  Claude Code installs as `/opt/homebrew/bin/claude` symlinked to
  `.../bin/claude.exe`, so any caller that resolves symlinks handed scode a
  name no entry matched. The harness lost its state auto-allow, which surfaced
  as the harness reporting that it was not logged in.

## [0.3.3] - 2026-08-13

### Fixed

- The audit log is now written through file descriptor 9 itself rather than
  through `/dev/fd/9` as a `tee` file argument. On Linux that path is a `/proc`
  symlink, so naming it re-resolved the log path on every run -- reopening the
  symlink-replacement race the descriptor exists to close, and (before 0.3.2)
  truncating the header. Only the stderr copy is addressed by path now, and
  stderr already belongs to the caller.

## [0.3.2] - 2026-08-04

### Fixed

- **Sandboxed execution never worked on Linux.** Every non-dry-run launch passed
  `--close-fds` to bubblewrap, an option that exists in no released version
  (checked against 0.9, 0.10, and 0.11), so `bwrap` aborted immediately with
  `Unknown option --close-fds`. Only `--dry-run` succeeded, which is why the
  test suite never caught it. The flag is removed, and the descriptor-closing
  guarantee it was meant to provide is now supplied on both platforms by
  `run_sandbox_engine_with_closed_fds` (previously macOS-only), verified by
  confirming an inherited descriptor does not reach the sandboxed process.

### Changed

- Coverage exclusion markers are renamed `SCODE_COVERAGE_EXCLUDE_START/END`
  (from `..._STATIC_...`) and now also bracket the macOS-only profile
  generation, which Linux-only kcov can never execute. With the runtime fix
  above, measured shell coverage is 82%, so `SHELL_COVERAGE_MIN` is back to 80.
- Log and audit-header tests that assert platform-neutral behavior now run on
  Linux instead of being skipped as macOS-only.

### Added

- CI enables unprivileged user namespaces on Linux so bubblewrap can actually
  start. Without it every runtime-sandbox test silently skipped, which is what
  hid the `--close-fds` defect.

## [0.3.1] - 2026-08-02

### Changed

- The shell line-coverage floor is now `SHELL_COVERAGE_MIN` (default 70%)
  instead of a hardcoded 80%. kcov is Linux-only and cannot execute the
  macOS-only halves of the script, so 80% was unreachable in CI. The JavaScript
  coverage gate is unchanged at 80%.
- The Homebrew formula now lives only in `bindsch/homebrew-tap`. The in-repo
  copy is removed; the two had already drifted apart.
- `PROGRAM_VERSION` is the single version string to edit for a release. The
  README banner, pinned install commit, and manual-install SHA-256 hashes are
  derived by `make release-pins`, and `make check-pins` verifies them.
- The packaging test derives the expected version from the source launcher
  instead of asserting a hardcoded string.

### Fixed

- Project configuration (`.scode.yaml`) and the config size limit were rejected
  on Linux. GNU `stat -f` reports *filesystem* status and exits 0, so the
  `stat -f … || stat -c …` fallback never fell through and the safety check
  compared filesystem IDs instead of inodes. Stat access now dispatches on an
  explicitly detected flavor through `_stat_field`.

### Added

- `scripts/release-pins.sh` plus `make release-pins` / `make check-pins`.

## [0.3.0] - 2026-08-02

### Added

- Known-harness support for Aider, Amp, Crush, Cursor Agent, GitHub Copilot CLI, Continue CLI, Kimi Code CLI, OpenHands CLI, Cline CLI, Kiro CLI, Auggie CLI, and Grok CLI.
- Config-only `grok_defense: true` mode: forces strict/env-scrub for detected Grok, blocks project Git metadata and dotenv files, and pins current Grok collection, telemetry, sync, compatibility, updater, memory, subagent, tool-search, and web-fetch controls off.
- Incident research and threat-model documentation in `docs/SECURITY-HARDENING.md`, plus `examples/sandbox-grok.yaml`.
- A reproducible `make coverage` gate for both the Bash launcher and Node preload, with an 80% minimum.

### Changed

- Strict-mode harness auto-allow now supports multiple config/state paths, including file-based config such as `~/.aider.conf.yml`.
- Refreshed default paths for OpenCode, Factory Droid, Qwen Code, Codemux, and Pi Coding Agent.
- Expanded default protection to SSH/signing keys, cloud/container/IaC credentials, package/VCS tokens, password-manager/keyring data, personal media, and shell/database histories on all platforms.
- Removed automatic macOS browser, cache, preferences, and Keychain carve-outs; `~/Library` stays blocked unless the user authorizes an exact subtree.
- Expanded environment scrubbing to current AI/cloud/CI/package credentials and shell/runtime injection variables.
- Project `.scode.yaml` policy is restrictive-only: it can add protections but cannot authorize paths or disable user/default controls.
- Strict harness state is read-only, and `--trust untrusted` disables harness-state auto-allows.
- JavaScript tests now require supported Node.js 22+; dependency installs are reproducible through the committed lockfile.
- SSH-agent variables and sockets are denied by default; forwarding now requires an explicit path and environment opt-in.
- Source/manual installation guidance now pins and verifies release artifacts; packaged installs include the license.

### Fixed

- Closed project-config, allow/block ordering, read-only, command auto-allow, synthetic `HOME`, runtime engine lookup, preload cleanup, and log symlink/terminal-injection bypasses.
- Linux now fails closed when a deep custom block cannot be mounted; macOS strict temp access is limited to the caller's private runtime directory.
- Logged runs forward termination signals and fail when requested logging cannot complete.
- JSON audit headers preserve exact command argument boundaries in an `argv` array.
- Chromium shell rewriting now handles shell `-c --`, newlines, brace/negation groups, nested wrappers, and `env` split-string/chdir forms without changing unrelated `shell: true` semantics.
- Custom blocks can no longer be hidden by project, child-allow, command, or preload mounts; conflicting project-wide blocks fail closed.
- Project configuration is pinned to a verified regular-file descriptor, rejects symbolic links/hard links, and is capped at 1 MiB.
- Grok history/dotenv blocks are mandatory while defense mode is active and reject overlapping allows.
- Shell rewriting now preserves nested single quotes, escaped separators, comments, absolute wrapper paths, and unsupported substitutions without corrupting commands.

## [0.2.0] - 2026-02-25

### Added

- JSON header (`#json:` line) in audit log files for machine-readable metadata, with full RFC 8259 §7 C0 control character escaping. External tools can extract it with `head -1 log | sed 's/^#json://' | jq .`. Legacy comment header preserved for backward compatibility.
- Property-based tests for JS shell tokenizer using fast-check (`test/no-sandbox.test.js`, 67 tests).
- `make test-js` target runs Node.js tests; `make test` now runs both JS and bats suites. Gracefully skips when Node < 18.13 or `node_modules` is missing; set `SCODE_REQUIRE_JS_TESTS=1` to force failure in CI.
- Exhaustive YAML parser edge-case matrix (12 new tests in `test/04_config.bats`).
- Exhaustive audit-log parser edge-case matrix (17 new tests in `test/08_audit.bats`).

### Fixed

- `--block` now denies `process-exec` (not just `file-read*`/`file-write*`) on macOS, preventing execution of binaries under blocked paths. Affects both default and strict mode profiles, including project-under-blocked-parent re-allows and explicit `--allow` overrides.
- `-p` no longer treated as a flag-with-value in wrapper parsing. Fixes `command -p chromium`, `time -p chromium`, and `timeout -p` where `-p` was consuming the next argument. `-p` remains correctly handled for `sudo` which does take a value.
- `bash -c -- "cmd"` now correctly handles the `--` terminator after `-c`. Both the JS preload injection (`lib/no-sandbox.js`) and bash harness detection (`detect_harness`) skip `--` to find the command string.
- Harness detection (`_detect_harness_from_args`) now skips `exec` prefix and `FOO=bar` variable assignments before the harness binary, matching real-world launch patterns like `exec claude`, `FOO=bar claude`, and `A=1 B=2 claude`.

### Changed

- Restructured `lib/no-sandbox.js`: pure functions moved above production guards for testability; conditional `module.exports` when `SCODE_TEST=1`.
- Log header written by shared `write_log_header_json()` (macOS and Linux call sites).
- Log file first line is now `#json:{...}` instead of `# scode session:`. Legacy comment header follows on subsequent lines. External parsers that assumed `# scode session:` was the first line need updating.

## [0.1.1] - 2026-02-24

### Fixed

- Shell flag detection now recognizes combined flags like `-ce`, `-ec`, `-xec` when patching Chromium `--no-sandbox` injection.
- Tokenizer correctly handles `FOO="bar baz"` and `FOO='bar baz'` shell assignments with embedded spaces.
- CLI `--block` now prevents command-binary auto-allow from bypassing the block.
- Wrapper patchers (`env`, `nice`, etc.) no longer double-inject `--no-sandbox` when it is already present.
- Audit log parser correctly extracts paths containing colons (e.g. `/tmp/my:file.txt: Permission denied`).
- Audit strips trailing slashes from `# allowed:` metadata entries, preventing false categorization mismatches.
- Config parser now supports YAML single-quote escaping (`'it''s-data'` → `it's-data`).
- `--block` on subdirectories inside the project directory now works correctly when the project itself is under a blocked parent (macOS and Linux).
- README preload scope updated to list all patched `child_process` APIs.
- README scrub pattern count corrected to 30.

## [0.1.0] - 2026-02-15

### Added

- Initial beta release of `scode`.
- Cross-platform sandboxing via `sandbox-exec` (macOS) and `bubblewrap` (Linux).
- Default mode and strict mode sandbox profiles.
- Config-driven policy support (`~/.config/scode/sandbox.yaml`).
- Environment scrubbing (`--scrub-env`) and browser no-sandbox preload support.
- Audit tooling: `scode audit` and `scode audit --watch`.
- Automated test suite and release gate checklist.
