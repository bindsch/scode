# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
