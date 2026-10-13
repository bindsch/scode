# Harness alignment — 2026-10-10

Historical report for released v0.6.0, commit
[21688369d239c0b6eeaf0abb238be3f7726f53d6](https://github.com/bindsch/scode/tree/21688369d239c0b6eeaf0abb238be3f7726f53d6).
Consolidated on 2026-10-13. Current contracts are in
[harnesses](../harnesses.md) and [environment](../environment.md).

## Scope and final decisions

The work compared known harness names, default state paths, and credential
variable names used by the installed routing tools. It added Antigravity
detection, updated scrub patterns, added exact-name keep-env exemptions, and
corrected Copilot's cross-platform cache documentation. The untracked support
matrix was not shipped and is not required evidence for this summary.

Antigravity v1.3.1 state inspection identified the Gemini root. A help probe
that wrote no files established only help-path behavior, not the absence of
other state or authentication stores. The later 2026-10-12 Keychain integration
observation is documented in the current harness guide.

No special `agent` recognition remains. A standalone binary with that name
is unknown; canonicalization still recognizes a symlink to `cursor-agent`.
Earlier absolute claims that every `agent` invocation stayed unknown were
incorrect. The generic alias checks were removed because they introduced
ambiguous wrapper/PATH handling. The normal canonical-name rule remained.

DeepSeek Harness was not added: no installed binary or verified state path
was available. `--keep-env` remained CLI-only and rejects injection names
and all exemptions under detected Grok defense. It validates names, not
credential meaning. CODEMUX control variables pass through, including the
credential-bearing `CODEMUX_CODEX_PROVIDER_API_KEY`; `LLM_API_KEY` is scrubbed.

## Final recorded validation

The [original report at the release commit](https://github.com/bindsch/scode/blob/21688369d239c0b6eeaf0abb238be3f7726f53d6/docs/align-0.6-report.md)
preserves intermediate runs. They refer to uncommitted review states without
individual commit IDs and are not independent release evidence.

| Recorded final command | Result | Evidence limit |
|---|---|---|
| `make lint` | Exit 0 | Report only; no committed raw log |
| `make test-js` | 101 passed, 0 failed | Report only |
| `bats test/` with inherited activation cleared | 580 total: 465 passed, 3 failed, 112 skipped; exit 1 | Outer sandbox blocked three sudo fixtures; runtime tests skipped |
| American English checker | Exit 0 | Report only |

The final Bats count fell from 591 to 580 after removing 11 tests for abandoned
alias-specific logic. Earlier filtered coverage runs were not a full release
gate and are not presented as final coverage evidence.

The v0.6.0 tag now exists. A later main-branch commit repinned install artifacts;
that did not change stale pins inside the tag. The rebuilt
[release procedure](../releases.md) addresses future tagged documentation.
