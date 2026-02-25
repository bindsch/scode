# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
