# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Recognize resolved Copilot, pi, Claude Code, and Codex package entry scripts
  by their `node_modules` directories so strict mode applies their state grants.
  Keep basename detection and `.exe` launcher support.
  Entry scripts are detected for their state directories, but credential sync
  requires the harness launcher binary because a script's interpreter comes
  from the caller's PATH.

## [0.6.1] - 2026-10-13

### Fixed

- Linux default mode now binds existing explicitly allowed host subtrees even
  when they were absent from its initial mounts. Final custom blocks and the
  project read-only rule still apply.
- Privilege-command restrictions are reasserted after explicit grants and
  command auto-allows on both platforms. They cover the documented names/paths,
  not renamed copies or all privilege mechanisms.
- Release selectors are updated before tagging and checked against either the
  working tree or an actual Git ref. Install procedures stop on verification
  failure and no longer embed a release commit's own hash.
- Development runtime checks now enforce the Node majors declared in the
  private manifest. Regression tests cover selectors, runtime policy, Linux
  grants, privilege masks, and canonical Cursor symlink detection.
- Preload tests clear inherited activation state and explicitly report skipped
  sudo fixtures when an outer sandbox denies executing them.

### Documentation

- Rebuilt the README and added a documentation index with focused installation,
  CLI, policy, configuration, harness/authentication, environment, browser,
  platform/signal, logging, accounting, security, Grok, development, and release
  guides. Consolidated guarantees, exceptions, schemas, path resolution,
  parsing rules, exit statuses, and runtime prerequisites.
- Corrected CLI help and example comments to match actual grants, trust presets,
  credential behavior, stderr replacement/capture, and codemux syntax.
  Corrected source comments for coverage exclusions, writable harness state,
  command exceptions, credentials, and all six patched Node APIs.
- Added private development-package identity, description, repository, and MIT
  metadata; documented why npm version/bin fields are absent. Release version
  is 0.6.1. Added an ignored repository scratch directory for verification.
- Consolidated dated historical reports and the completed release plan behind
  an archive index. Removed stale TODO guidance, recorded evidence limits,
  and moved Antigravity authentication limits into the harness guide.
- Reordered release checks before publication, including tagged documentation,
  merged coverage sidecars, controlled Claude verification, and bottle checks.
  Documented optional hook prerequisites. Prepared local v0.5.0/v0.6.0 release
  bodies for operator publication.
- Corrected released notes below without changing the historical features:
  v0.6.0 Cursor aliases, keep-env validation, and CODEMUX credential exception;
  v0.5.0 date, credential/link exceptions, accounting byte bound, signal/log
  guarantees, and descriptor semantics; v0.4.0 opt-out wording; v0.2.0 test count.
  Old immutable tagged READMEs still contain previous-release install pins.

## [0.6.0] - 2026-10-10

### Added

- **Known-harness support for Google Antigravity CLI (`agy`).** `agy` shares
  the Gemini CLI root: the installed binary's own strings (v1.3.1) and the
  live `~/.gemini` tree put its settings and cache under
  `~/.gemini/antigravity-cli`, shared config under `~/.gemini/config`, and
  root-level files (`GEMINI.md`, `AGENTS.md`, `projects.json`) beside them —
  so strict mode auto-allows `~/.gemini`, and allowing only the two
  subdirectories would miss the root-level state. Sandboxed `agy` runs no
  longer warn "not a known harness". The Cursor Agent's alias `agent` is
  not recognized by that basename alone. **Correction (2026-10-13):** a
  standalone `agent` executable is unknown, but a symlink resolving to
  `cursor-agent` is recognized after canonicalization. codemux 0.12.0 uses
  the `cursor-agent` launcher name.
- **`--keep-env NAME[,NAME...]`** exempts exact variable names from
  `--scrub-env`. An outer launcher that has already authenticated (codemux's
  provider overrides) needs to deliver one named credential through an
  otherwise scrubbed environment; the flag is the opt-in for that. A name
  containing `=` or whitespace is refused, as is an empty list entry
  (leading, middle, or trailing) and any glob-looking entry (entries are
  never expanded against the working directory). Startup-injection and
  loader variables (`LD_*`, `DYLD_*`, `NODE_OPTIONS`, `BASH_ENV`, `ENV`,
  `ZDOTDIR`, `PYTHONPATH`, `PYTHONHOME`, `RUBYOPT`, `PERL5OPT`, `PERL5LIB`,
  `PERLLIB`, `JAVA_TOOL_OPTIONS`, `_JAVA_OPTIONS`, `GIT_CONFIG_*`,
  `GIT_ASKPASS`, `SSH_*`) are refused outright. **Correction (2026-10-13):** other syntactically
  valid names, including PATH, are accepted; this is not credential classification. The flag is
  repeatable and deduplicates; `--dry-run` prints the kept names (never their
  values); passing it with no source of scrubbing (the flag or a config
  `scrub_env`) warns that it has no effect; and under Grok defense it is
  refused outright, since that scrub cannot be relaxed for a Grok command.
  There was no pass-through mechanism before.
- **Scrub patterns for the credentials the current routing stack reads:**
  `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `CODEX_API_KEY`,
  `ZAI_API_KEY`, `ZHIPU_API_KEY`, `MOONSHOT_API_KEY`, `KIMI_API_KEY`,
  `KIMI_MODEL_API_KEY`, `DASHSCOPE_API_KEY`, `QWEN_API_KEY`,
  `COPILOT_GITHUB_TOKEN`, `CURSOR_API_KEY`, `FACTORY_API_KEY`, and
  `LLM_API_KEY` (the OpenHands and Aider override credential; a launcher
  that injects it keeps it with `--keep-env LLM_API_KEY`). A scrubbed run
  previously handed all of these to the child. Enumerated provider configuration
  (base URLs, model names, override-delivery channels such as
  `OPENAI_API_BASE`, `LLM_BASE_URL`, `GOOSE_PROVIDER`, `KIMI_MODEL_*` other
  than the key, `PI_CODING_AGENT_DIR`, `OPENCODE_CONFIG`) and the
  `CODEMUX_*` control variables are deliberately not scrubbed: they route a
  run, except that **CODEMUX_CODEX_PROVIDER_API_KEY authenticates** the
  Codex override (wording corrected 2026-10-13):
  `CODEMUX_CODEX_PROVIDER_API_KEY` carries the Codex override API key, so a
  scrubbed run still delivers it; the caller controls that by exporting the
  override only for the runs that need it.

### Fixed

- The README called the `~/.cache/copilot` harness auto-allow Linux-only
  while the code applied it on every platform. The code was right: the
  Copilot CLI's own code consults `~/.cache/copilot` (the XDG fallback) in
  the same candidate list on every platform, with `~/Library/Caches/copilot`
  as the macOS primary — which stays blocked with the rest of `~/Library`.
  The README now matches the code.

## [0.5.0] - 2026-10-08

> Documentation correction, 2026-10-13: the release/tag date is October 8.
> October 7 was the previous heading. Credential, accounting, signal, and
> logging descriptions below consolidate the released behavior and its limits.

### Changed

- Shell coverage is collected on macOS and Linux and gated over matching
  merged reports at 80%. Each platform skips the other's runtime tests.
  The descriptor-closing launcher is excluded from measurement; runtime tests
  still launch through it. Eight exact-signal tests skip under kcov because
  its extra parent changes delivery; ordinary tests retain them.

### Security

- Successful macOS Claude Keychain synchronization now writes an access-only
  credential: `refreshToken` is emptied and `refreshTokenExpiresAt` removed.
  This avoids competing copies rotating the same refresh grant. The access
  token remains a bearer credential readable by the sandbox.
- A mirrored file with a refresh token is backed up privately before rewriting.
  If Keychain is unreadable or the required backup/rewrite fails, launch is
  refused when the mirrored refresh token is detected. Successful rewrites
  prune older backups, never newer concurrent ones.
- A usable Keychain access token replaces the file unless it already matches
  without a refresh token. Expired Keychain tokens are not copied; an existing
  mirrored refresh token can still be removed. The earlier expiry-order rule
  no longer selects the credential.
- File-only macOS credentials with no Keychain item remain untouched.
  Linux does not use synchronization. Opt-out, wrappers, project-local
  binaries/state, and symlinks skip the copy; applicable mirrored-token
  refusal checks remain. Synchronization does not rewrite through links,
  but refusal checks can read their targets. Opt-out does not disable all
  authentication. See [the current decision table](docs/harnesses.md#claude-code-on-macos).

### Added

- Opt-in JSON-line accounting through `SCODE_ACCOUNT_FILE` and optional
  `SCODE_ACCOUNT_ID`, including setup/launch failures after argument parsing.
  Help, version, and audit do not record. IDs accept letters, digits, and
  `. _ : -` up to 128 characters; invalid IDs are dropped, not truncated.
- Records contain exit status, duration, and pre-teardown macOS private-scratch
  usage. Linux attempted launches report null size with
  `tmpfs_unmeasurable`; dry-runs and Linux engine-not-found report
  `no_scratch`. macOS can allocate scratch before engine validation.
- Each append contains an at-most-800-byte JSON payload **plus one newline**.
  Oversized paths become null before a still-oversized record is dropped.
  Append failure warns and attempts a terminating newline without changing
  the run's status. Variables are removed from the child environment;
  child-writable sinks remain forgeable.

### Fixed

- Scratch cleanup repairs owner directory permissions and retries a bounded
  number of times, without changing linked file permissions.
- Accounting rejects non-regular and symlink sinks. It opens an append
  descriptor at arm time, fingerprints parent directories and sink identity,
  and revalidates before accepting a record. The descriptor is the destination;
  revalidation does not perform a new destination open or assume all children
  have exited. SIGPIPE/SIGXFSZ during exit diagnostics or accounting do not
  replace the run status or skip cleanup.
- Logged and unlogged engines run as children with explicit stdin preservation
  and final exec so forwarding targets the engine PID. System Python, with
  system Perl fallback, restores INT/QUIT/PIPE/XFSZ dispositions.
  Interpreter startup controls and macOS developer-tool selection are carried
  safely across that launcher and restored for the engine. Without either
  interpreter, ignored dispositions and launch-window signal loss remain.
- INT/HUP/TERM are not forwarded when scode owns the terminal foreground group;
  PID-only signals there do not reach the engine. Without terminal ownership,
  forwarding can duplicate group-directed signals. The engine's eventual
  status is retained unless logging failure or scode's QUIT handling changes
  the result. QUIT is not forwarded: scode exits 131, and PID-only QUIT can
  leave an engine alive. Prelaunch INT uses a descriptor-backed pending marker
  and bounded handshake; TERM/HUP are delivered after launch.
- The log writer remains alive while an engine handles a signal. A bounded
  drain check waits for a per-run marker after engine reap. Writer failures
  make a successful run nonzero; a drained writer stopped after its grace
  warns about possible stderr-mirror loss. Late daemonized-child output can
  be lost. The saved marker is not authenticated by `audit`, and a
  child-writable log can be forged.

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
  the copy. **Correction (2026-10-13):** existing files or independently
  supplied credentials can still authenticate. Trade-off, stated in
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
- Property-based tests for JS shell tokenizer using fast-check (`test/no-sandbox.test.js`, 82 tests; historical count corrected 2026-10-13).
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
