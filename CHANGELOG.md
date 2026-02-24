# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
