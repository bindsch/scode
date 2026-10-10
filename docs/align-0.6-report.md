# align-0.6: scode aligned with the harnesses and providers in use

Branch `align-0.6`, from scode main at 0.5.0. Scope: the scode half of the
gaps named in sections 1–3 of `scratch/support-matrix-audit.md`. Every path
and pattern below was verified from the installed binaries and codemux's own
package on this machine (codemux 0.11.0 at `/opt/homebrew/opt/codemux`);
nothing was guessed from web copy.

## 1. Known harnesses

### `agy` (Google Antigravity CLI) — added

`KNOWN_HARNESSES` now contains `agy`; strict mode auto-allows `~/.gemini`.

How the paths were verified, in order:

1. **Binary identification.** `command -v agy` → `~/.local/bin/agy`
   (symlinked from `/opt/homebrew/bin/agy`), a 178 MB Go binary reporting
   `agy --version` → `1.3.1`. `agy --help` exits 0.
2. **`strings` on that binary.** Its embedded changelog and help text name,
   as paths it reads and writes: `~/.gemini/antigravity-cli/settings.json`
   ("The CLI is configured via `~/.gemini/antigravity-cli/settings.json`"),
   `~/.gemini/antigravity-cli/cache/projects.json` (centralized project
   discovery), `~/.gemini/config/` (`config.json`, `hooks.json`,
   `mcp_config.json`, plugins, rules, skills, workflows, `projects/`),
   `~/.gemini/GEMINI.md`, and `~/.gemini/AGENTS.md` (global rules, read as
   symlinks).
3. **The live tree.** `~/.gemini` on this machine, written by that same
   binary, contains both `antigravity-cli/` (conversations, cache, brain,
   `cli.log`, crashes) and `config/` (`config.json`, `hooks.json`,
   `mcp_config.json`, `projects/`), plus root-level `GEMINI.md`,
   `projects.json`, `installation_id`, `history`.
4. **Scratch-HOME dry probe.** `HOME=<scratch> agy --help` exits 0 and
   writes nothing under the scratch home, so no hidden fourth location
   exists outside what the strings show.

Decision: auto-allow the whole `~/.gemini` root, not just the two
subdirectories. agy reads and writes root-level files (`GEMINI.md`,
`projects.json`, `installation_id`), so allowing only
`~/.gemini/antigravity-cli` and `~/.gemini/config` would leave a strict run
unable to persist its state. This is the same unit the `gemini` entry
already allows; the two harnesses share the root by design (the Antigravity
changelog describes its config as part of the Gemini CLI tree).

No `AGY_*`/`GEMINI_*` variable relocates that root the way `GROK_HOME`
does for Grok — the strings show only feature and display toggles
(`AGY_CLI_LOGO_STYLE`, `AGY_CLI_FORCE_OSC8`, onboarding markers), so there
is no environment-controlled-root exception to carry over.

### `agent` (Cursor Agent alias) — not recognized

`agent` is not a known harness and never maps to `~/.cursor`. The name is
too generic: any repository can ship a script called agent. Rounds sc2
through sc10 (section 7) tried to recognize it safely — resolution to the
launcher file, the project-owned rule, the home-rooted exception, the
PATH-reassignment prefix threaded through `env`, shell `-c`, and wrapper
recursion — and every review round found another bypass (substring match,
project-owned launcher, PATH assignment prefix, `env -P`, `env
--unset=PATH`, `env -S`, prompt text inside `sh -c`). Round sc11 removed
the surface instead of patching it again: no resolution, no PATH scan, no
`agent` arm anywhere.

Nothing is lost by the removal. The real launcher name is `cursor-agent`,
present in every install beside the `agent` symlink (verified here:
`~/.local/bin/agent` and `~/.local/bin/cursor-agent` are symlinks to the
same versioned launcher,
`~/.local/share/cursor-agent/versions/2026.08.11-e8db854/cursor-agent`),
and `cursor-agent` keeps the plain bare-name rule it has had since 0.5.0:
strict mode auto-allows `~/.cursor` for it. codemux 0.12.0 launches the
Cursor Agent under that name. A bare `agent` command stays an unknown
command: usual warning, no strict-mode auto-allow, in dry runs and real
runs alike.

### `dsh` (DeepSeek Harness) — not added, documented instead

`command -v dsh` finds nothing on this machine. The task allows adding it
if its own docs name its config dir; the only sources at hand are the
third-party articles cited by the audit, and web search was not available
in this session, so no first-party path evidence exists. Guessing a
`~/.dsh`-style default is exactly what the task forbids. Documented here as
not installed; add it when the binary or its upstream docs are available to
verify against.

## 2. Environment scrub

### New patterns (all verified as credential-bearing)

Sourced from codemux 0.11.0's own credential allowlist
(`/opt/homebrew/opt/codemux/libexec/src/environment.ts`,
`ALLOWED_CREDENTIAL_ENV`) and its README "Provider overrides" section, then
matched against the task list:

| Pattern | Who reads it | Evidence |
|---|---|---|
| `ANTHROPIC_AUTH_TOKEN` | Claude Code/zai gateway route | codemux README (claude override carries the key in it); `environment.ts` zai entry |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code OAuth | `environment.ts` claude entry; README says codemux strips it from override runs |
| `CODEX_API_KEY` | Codex CLI ≥ 0.154 | `environment.ts` codex entry ("0.154 reads CODEX_API_KEY") |
| `ZAI_API_KEY` | Z.AI (source credential) | codemux README "Z.AI Adapter Credentials" (env form; translated then removed from the child env) |
| `ZHIPU_API_KEY` | Zhipu direct (Z.AI's parent) | task list; the zai route is Zhipu's endpoint |
| `MOONSHOT_API_KEY` | Moonshot platform (Kimi's API) | task list; Moonshot is the Kimi model provider |
| `KIMI_API_KEY` | Kimi Code direct credential | `environment.ts` kimi entry ("KIMI_API_KEY and OPENAI_API_KEY are the direct-credential paths") |
| `KIMI_MODEL_API_KEY` | Kimi Code synthesized provider | `adapters/kimi.ts:107` (`KIMI_MODEL_API_KEY: override.apiKey`) — the credential in the `KIMI_MODEL_*` group |
| `DASHSCOPE_API_KEY` | Alibaba DashScope (Qwen) | `environment.ts` qwen entry |
| `QWEN_API_KEY` | Qwen Code | `environment.ts` qwen entry |
| `COPILOT_GITHUB_TOKEN` | GitHub Copilot CLI | `environment.ts` copilot entry |
| `CURSOR_API_KEY` | Cursor Agent | `environment.ts` cursor entry |
| `FACTORY_API_KEY` | Factory Droid | `environment.ts` droid entry |

`GOOGLE_API_KEY` and `GEMINI_API_KEY` (the agy/gemini credentials) were
already covered — `GOOGLE_*` prefix and the existing `GEMINI_API_KEY`
pattern — so nothing new was needed for them.

### Left unscrubbed, and why

- `OPENAI_API_BASE`, `LLM_BASE_URL`, `LLM_MODEL` — the channel codemux uses
  to deliver an override to Aider and OpenHands (litellm's `openai/` route).
  These are configuration and stay. The channel's credential,
  `LLM_API_KEY`, is scrubbed (round sc4): it carries a key, so it belongs
  with the patterns; a launcher that injects it for an override keeps it
  with `--keep-env LLM_API_KEY`.
- `GOOSE_PROVIDER`, `GOOSE_MODEL`, `OPENAI_HOST`, `OPENAI_BASE_PATH` —
  goose's pure-environment provider configuration; the group's credential
  is `OPENAI_API_KEY`, which is scrubbed (existing pattern).
- `KIMI_MODEL_*` other than the key — model, endpoint, and token-cap
  configuration (`KIMI_MODEL_MAX_COMPLETION_TOKENS`,
  `KIMI_MODEL_MAX_CONTEXT_SIZE`); the credential in the group,
  `KIMI_MODEL_API_KEY`, is scrubbed.
- `PI_CODING_AGENT_DIR`, `OPENCODE_CONFIG` — paths to per-run private
  configuration codemux creates; not credentials.
- `CURSOR_API_ENDPOINT`, `ANTHROPIC_BASE_URL` — endpoint URLs.
- `CODEMUX_*` (including `CODEMUX_<AGENT>_PROVIDER_API_KEY`) — codemux's
  control variables. Codex's override delivers its key through the
  environment under `CODEMUX_CODEX_PROVIDER_API_KEY`
  (`codex-provider.ts:93`), and `config.toml`'s `env_key` names it;
  scrubbing it blindly would cut the sandboxed codex off from the override
  codemux configured, exactly the failure the audit warned about. The
  operator-facing `CODEMUX_*` names are routing input, not ambient
  credentials.

### `--keep-env NAME[,NAME...]` — new flag

scode had no pass-through mechanism (no `--allow-env`/`--pass-env` flag or
config key; verified by grep over `scode`, `README.md`, `docs/`). The new
flag:

- exempts exact variable names from the scrub at `scrub_env` time (no glob
  patterns — patterns could exempt a family by accident);
- refuses a name containing `=`, whitespace, or any character outside
  `[A-Za-z0-9_]`, and refuses empty list entries (`A,,B`, trailing comma);
  exit 1 at parse time;
- is repeatable and deduplicates;
- prints the kept names (never values) in `--dry-run` under
  `--scrub-env active`;
- warns when passed with no source of scrubbing (no flag, config, or Grok
  defense turned the scrub on), after every source of `SCRUB_ENV` has
  resolved.

Intended consumer: codemux, which for a provider-override run injects one
of the now-scrubbed credentials (`ANTHROPIC_AUTH_TOKEN`,
`KIMI_MODEL_API_KEY`, `OPENAI_API_KEY`, ...) and will pass
`--keep-env <that name>` so the override survives a `--sandbox-scrub-env`
run. Verified end to end on this machine: with `--scrub-env
--keep-env ZAI_API_KEY`, a real sandboxed child saw `ZAI_API_KEY` while a
sibling `QWEN_API_KEY` was scrubbed and listed in the scrub summary; the
kept name does not appear in the summary.

## 3. Copilot cache path — README fixed, code kept

The code auto-allows `~/.cache/copilot` on every platform; the README said
"(Linux)". The Copilot CLI's own code decides it: the installed 1.0.85
darwin-arm64 binary embeds its cache resolution —

- macOS: `~/Library/Caches/copilot` (primary),
- the XDG fallback `$XDG_CACHE_HOME/copilot` (default `~/.cache/copilot`)
  appears in the same candidate list on every platform, alongside
  `$COPILOT_HOME/pkg` and `~/.copilot/pkg`.

So the CLI itself consults `~/.cache/copilot` on macOS too, and the
unconditional auto-allow is correct. The macOS primary cache
(`~/Library/Caches/copilot`) stays blocked with the rest of `~/Library`, by
scode's stated no-carve-outs policy. The README table and a note under the
harness table now match the code.

## 4. Version, changelog, docs

- `PROGRAM_VERSION="0.6.0"`.
- `CHANGELOG.md`: `## [0.6.0] - 2026-10-10` (Added / Fixed).
- README: banner, options table row, examples, harness table rows for `agy`
  and `agent` (the `agent` row was removed again by round sc11), copilot
  note, `--scrub-env` section rewritten with the new credential list and a
  `--keep-env` subsection, "Batteries included" bullet updated.
- `docs/RELEASE-GATE.md`: unchanged — no gate step changes. The new flag
  falls under existing step 5 (flags documented in README and `--help`),
  which it is.
- README install pins (commit, hashes) are untouched: `make release-pins`
  derives them from the v0.6.0 tag, which does not exist yet; the banner
  version was updated by hand as the one line release-pins does not gate on
  the tag for.

## 5. Gates (run in this session, 2026-10-10)

- `make lint` (shellcheck): exit 0.
- `make test-js`: 101 tests, 101 pass, 0 fail, exit 0.
- `bats test/`: 576 tests — 573 ok, 3 not ok, plus this environment's
  skips. The three failures (`preload injects command flag with sudo -u
  wrapper`, `spawnSync sudo -u wrapper`, `spawnSync sudo --user= wrapper`)
  need `sudo`, which this agent session's own sandbox forbids
  (`operation not permitted`). They fail identically against the pristine
  0.5.0 script and pass in CI, which is not itself sandboxed. The session
  also exports `SCODE_SANDBOXED=1`, which leaks into node children; the
  runs above used `env -u SCODE_SANDBOXED` so the one test sensitive to it
  (`preload does not patch when SCODE_SANDBOXED is not set`) runs clean.
- Test count vs the 0.5.0 suite: 558 → 576 (+18 new tests, verified by
  counting `@test` blocks in the diff: 2 strict auto-allow, 2
  shortcut/no-warning, 3 scrub-boundary, 11 `--keep-env`). The kcov runs
  below close the arithmetic: with the three sudo tests filtered out, the
  pristine 0.5.0 suite executes 555 tests with 0 failures and the 0.6.0
  suite executes 573 with 0 failures — a delta of exactly 18.
- `make coverage`: the Makefile recipe aborts at the bats step in this
  session (`set -e` plus the sudo trio above), so the recipe (Makefile
  lines 79–95) was reproduced exactly, with one substitution:
  `bats test/ --negative-filter 'sudo -u|spawnSync sudo'`, which excludes
  exactly those three tests (a grep over the suite confirms the regex
  matches no other test). Results, both runs on this host under kcov 43:
  - Shell line coverage **69.00%** (macOS-only report). Same-recipe
    baseline on pristine 0.5.0 (`git archive HEAD` into a scratch
    export): **68.60%**. The diff raises same-environment coverage; the
    new lines are exercised by the new dry-run/parse tests, which run on
    every platform. Both numbers understate what CI's macOS collector
    measures, because this session's sandbox also forces the
    runtime-sandbox tests to skip; the 80% floor applies to the merged
    macOS+Linux reports in CI, which 0.5.0 established and this diff does
    not weaken.
  - The single-platform gate passed at its configured local floor
    (`COVERAGE_SINGLE_MIN=0`; the merged floor runs in CI).
    `coverage/shell-darwin.cobertura.xml` and its source SHA-256 were
    written (gitignored path).
  - JS coverage gate (c8, ≥80% lines/functions/branches/statements):
    passed — 86.06% lines, 84.21% functions, 100% branches, 86.06%
    statements.
- `python ~/.claude/skills/humanizer/scripts/check_american.py` on
  `README.md`, `CHANGELOG.md`, and this report: exit 0.

## 6. Left out, and why

- `dsh`: not installed, no first-party docs reachable, no verified paths —
  skipped (above).
- No usagemux/codemux changes: those are the other tools' halves of the
  audit gaps; this task is the scode part.
- `--keep-env` is CLI-only (no config key, no `SCODE_KEEP_ENV`): the
  exemption weakens the scrub, so it should be a deliberate per-invocation
  choice by the caller that knows which credential it is delivering, not a
  sticky file default. codemux can compose it into its `scode` argv.

## 7. Round sc2: review fixes

A three-lens review (correctness, security, contracts) of the staged diff
returned five distinct findings. Every one is fixed at the root cause, and
each behavioral fix carries a regression test.

### correctness-2 1 — `--keep-env` parser expanded globs

The old parser looped over an unquoted `$raw`, so each comma-separated entry
went through pathname expansion against the caller's directory: next to a
file named `AWS_notes`, `--keep-env 'AWS_*'` exempted `AWS_notes` and exited
0, contradicting the documented "exact names, no patterns".

Fix: the split is `read -ra` on the quoted value (`scode:2478`), which
performs no pathname expansion — a glob-looking entry stays the literal
string and fails the name check (`scode:2480`). Test:
`test/05_environment.bats:569` creates the matching file in the working
directory and asserts the entry is refused as a name.

### correctness-2 2 — trailing empty `--keep-env` entry was accepted

With `IFS=,`, bash drops one trailing empty field during splitting (a
`for` loop over the expansion and `read -ra` both do), so `--keep-env
ZAI_API_KEY,` was accepted while `,ZAI_API_KEY` and `A,,B` were refused —
the opposite of what README and CHANGELOG promised. The round-sc1 test
covered only `"ZAI_API_KEY,,"`, whose middle empty field masked the gap.

Fix: empty entries are refused from the raw value before splitting — the
`case` guard at `scode:2467-2472` rejects a leading comma, trailing comma,
or double comma, because field splitting alone cannot surface a trailing
empty. A newline in the list is refused the same way (`scode:2460-2463`);
`read` would otherwise consume one line and silently drop the rest. Test:
`test/05_environment.bats:557` covers `A,,B`, `A,`, `,A`, and a lone comma.

### correctness-2 3 / security 2 — the bare name `agent` auto-allowed `~/.cursor`

`agent` had been added to `KNOWN_HARNESSES` outright, so under `--strict`
any command whose basename is `agent` — a project script, anything — got
read-write access to `~/.cursor` with no check that it is the Cursor
launcher.

Fix: `agent` is removed from `KNOWN_HARNESSES` (`scode:68`). The name is
recognized only when the command it names resolves, after symlinks, to a
file that is the launcher itself (named cursor-agent, outside the project) —
`_is_cursor_agent_binary` (`scode:1716`), hooked into detection at
`scode:1907-1913`. Resolution mirrors `COMMAND[0]`: absolute paths as-is,
relative paths against the project dir, bare names through the caller's
PATH from the project dir. Any other `agent` stays an unknown command:
usual warning, no strict-mode auto-allow. The `agent` arm of
`get_harness_config_paths` (`scode:2108`) is reached only after that check,
and `--help` states the rule (`scode:605-609`). Tests, both with fake
binaries laid out like the real install: `test/07_harness.bats:330`
(strict auto-allow for a symlinked launcher under a cursor-agent path) and
`test/07_harness.bats:348` (an unrelated `agent` warns, no auto-allow);
PATH-lookup variants at `test/05_environment.bats:183` and
`test/05_environment.bats:199`.

### security 1 — `--keep-env` could exempt startup-injection variables

The parser checked only that a kept name was a valid variable name, so
`--keep-env LD_PRELOAD` (or `NODE_OPTIONS`, `BASH_ENV`, `SSH_AUTH_SOCK`,
...) re-admitted exactly the code-injection vectors the scrub exists to
remove.

Fix: the refused set `KEEP_ENV_REFUSED` (`scode:2439-2447`) — `LD_*`,
`DYLD_*`, `NODE_OPTIONS`, `BASH_ENV`, `ENV`, `ZDOTDIR`, `PYTHONPATH`,
`PYTHONHOME`, `RUBYOPT`, `PERL5OPT`, `PERL5LIB`, `PERLLIB`,
`JAVA_TOOL_OPTIONS`, `_JAVA_OPTIONS`, `GIT_CONFIG_*`, `GIT_ASKPASS`,
`SSH_*` — is checked per name in `parse_keep_env` (`scode:2484-2491`); a
match is exit 1 and the error prints the full set. Keep-env is for
credentials a launcher injects on purpose, never loader or startup names.
Documented in README (`README.md:584`, options row `README.md:143`) and
CHANGELOG. Test: `test/05_environment.bats:583` walks every exact name and
prefix class and asserts the refusal and the printed set.

### security 3 — tests asserted API keys survive the scrub

The round-sc1 boundary tests asserted that `LLM_API_KEY` and
`CODEMUX_CODEX_PROVIDER_API_KEY` survive `--scrub-env`, enshrining
API-key-shaped names as values the scrub keeps.

Fix: the kept names in those tests are non-credential markers now. The
provider-configuration test (`test/05_environment.bats:461`) drops
`LLM_API_KEY` and adds the synthetic `SCRUB_BOUNDARY_MARKER`; the codemux
test (`test/05_environment.bats:498`) drops
`CODEMUX_CODEX_PROVIDER_API_KEY` and asserts only the routing names. Real
credential names stay covered where they belong, by the scrub test at
`test/05_environment.bats:410` (and the pre-existing pattern tests). The
scrub lists themselves are unchanged; only the tests stopped asserting
that key-shaped values pass through.

### contracts — stale test title for the copilot cache auto-allow

`test/07_harness.bats:294` still titled the `~/.cache/copilot` auto-allow
"Linux cache" after this changeset had corrected every other description to
platform-agnostic. The title now reads "strict+copilot auto-allows config
and the XDG cache on every platform"; the assertions were already correct
and are unchanged.

### Gates (run in this session, 2026-10-10)

- `make lint` (shellcheck): exit 0.
- `make test-js`: 101 tests, 101 pass, 0 fail, exit 0.
- `make test` under `env -u SCODE_SANDBOXED`: 580 bats tests — 577 ok,
  3 not ok. The three failures are the sudo-wrapper preload trio that
  round sc1 already documented: this session's own sandbox forbids `sudo`
  (`operation not permitted`), they fail identically against pristine
  0.5.0, and they pass in CI. Without `env -u SCODE_SANDBOXED` the
  session's exported `SCODE_SANDBOXED=1` also fails
  "preload does not patch when SCODE_SANDBOXED is not set", for the same
  round-sc1 reason. Runtime-sandbox tests skip in this session as before.
- Test count vs the round-sc1 suite: 576 → 580 (+4: two new `agent`
  shortcut tests replacing one, the glob test, the refused-names test;
  the empty-entry test was rewritten in place, and the strict `agent`
  test became the launcher/unrelated pair).
- `python ~/.claude/skills/humanizer/scripts/check_american.py` on
  `README.md`, `CHANGELOG.md`, and this report: exit 0.

### Round sc2, second review: the `agent` match

The second review found `_is_cursor_agent_binary` matching the substring
`cursor-agent` anywhere in the resolved path, so a checkout named
`cursor-agent-plugins` shipping `bin/agent` passed as the launcher. The helper
now requires the resolved file to be named `cursor-agent` and to live outside
the project directory (`scode`, `_is_cursor_agent_binary`). Tests: the
existing launcher test builds its fake install outside the project, and a
new test proves both a `bin/agent` under a `cursor-agent-plugins` checkout
and a project-owned file named `cursor-agent` stay unknown commands.

### Round sc4, fourth review (PASS): three minors

- The documented `agent` rule now matches the code everywhere (`scode`
  header comment, README harness row, this report).
- `LLM_API_KEY` is a credential, not configuration: it joined
  `SCRUB_PATTERNS`; the README, CHANGELOG and the comment above the
  patterns say so, and codemux keeps it through `--keep-env` for an
  OpenHands override. Test: `--scrub-env` strips it; `--keep-env
  LLM_API_KEY` keeps it.
- The `--keep-env` refusal message lists the refused names separated by
  spaces (it was joined by the comma `IFS` of the split).

### Round sc5, fifth review (PASS): three minors

- CHANGELOG: the `agent` rule now reads as the code does (launcher file
  outside the project) and the scrub-pattern list names `LLM_API_KEY`.
- A PATH reassignment anywhere in the command line disables `agent`
  recognition (`_command_reassigns_path`, scanned over the whole `COMMAND`
  rather than the recursed segment, after the sixth review showed a prefix
  flag was lost through `env` and shell `-c` strings): the lookup reads the
  caller's PATH and would otherwise judge a different file than the one
  that runs. Test: the launcher behind `env PATH=... agent`,
  `sh -c "PATH=...; agent"` and `sh -c "export PATH=...; agent"` stays
  unknown.

### Round sc7, seventh review: two findings

- major: a real run canonicalizes `COMMAND[0]` before detection, so an
  `agent` symlink to a project-owned launcher named `cursor-agent` reached
  the detector under its resolved name and the bare-name `cursor-agent`
  rule accepted it. `_resolved_inside_project` now withholds the
  `cursor-agent` recognition for a launcher inside the project (a name that
  does not resolve keeps the bare-name rule for dry-run renderings). Test:
  a real sandboxed run of the project-owned launcher, under both spellings,
  stays an unknown command.
- minor: `--keep-env` could relax the Grok defense scrub. It is refused
  outright when the defense is active for a Grok command; README and a
  config test say so.

### Round sc8, eighth review (PASS): one minor

The PATH-reassignment rule now covers the bare `cursor-agent` name as
well (`_detect_harness_from_args`): `env PATH=bin cursor-agent` and the
shell forms stay unknown commands. Test added.

### Round sc10, tenth review: six findings

A ninth three-lens review returned two correctness findings, one security
finding, and three contracts findings. Every one is fixed at the root
cause; each behavioral fix carries a regression test.

#### correctness 1 — a prompt mentioning `PATH=` stopped recognition

The sc5 guard rescanned the whole `COMMAND` from the `agent`/`cursor-agent`
arms, so free-text prompt arguments matched: `scode -- cursor-agent -p "fix
the PATH=/opt/bin line in the Makefile"` warned "not a known harness" and
strict mode withheld `~/.cursor` — a regression from 0.5.0, which recognized
`cursor-agent` unconditionally. A reassignment can only change which binary
runs if it comes before the command word; a prompt argument cannot.

Fix: the guard now walks only what runs before the command word, threaded
through the recursion instead of rescanning. `_detect_harness_from_args`
takes a leading reassignment flag (scode:1916-1922) that the `env`, shell,
and wrapper branches pass down, so a prefix seen at an outer level survives
(the sc6 property) without touching anything after the command word. The
flag is set by an assignment-prefix token (scode:1939-1941), by `env`
arguments up to the command word (next finding), and by the text of a shell
`-c` string, scanned whole because it is executed whole — `PATH=`/`export
PATH=` anywhere in it counts (scode:2003-2008). The `cursor-agent`
(scode:1963) and `agent` (scode:1983) arms read the flag. `detect_harness`
now delegates in one line (scode:2207): its second shell-`-c` walk was dead
code that would have lost the threaded flag and re-recognized what the
recursion had just withheld. `_command_reassigns_path` is gone; its
per-token match lives on in `_text_reassigns_path` (scode:2160).
Test: `test/07_harness.bats:743` — the prompt forms of both spellings are
recognized again.

#### security 1 — `env -P<dir>` ran a different file than the one judged

macOS `env -P dir` searches `dir` for the utility instead of `PATH`, and
getopt accepts the joined form. The `env` branch skipped every `-`-prefixed
token, so `scode -- env -Pbin agent` — with a project-owned `bin/agent` and
the real launcher on PATH — handed detection the bare `agent`, which
resolved through the caller's PATH to the real launcher and reported the
harness, while `env` executes the project's own file with `~/.cursor`
read-write. The separate form `-P dir` failed safe only by accident (`dir`
was taken as the command).

Fix: the `env` branch now recognizes every flag that changes lookup
(scode:2021-2075): `-P` and the joined `-Pdir` set the flag, and the
separate `-P dir` form consumes its value instead of mistaking it for the
command; `-S`/`--split-string` set it (their string is re-split and
executed) and consume the string; `-i`/`--ignore-environment` set it; `-u
PATH` and the joined `-uPATH` set it, while `-u NAME` still only consumes
its value. Test: `test/07_harness.bats:763` — `-Pbin` with a planted
project `bin/agent`, `-P <dir>`, `-i`, and `-u PATH` all stay unknown
commands, for both spellings.

#### correctness 2 — running from `$HOME` withheld Cursor Agent

`_resolved_inside_project` and the final check of `_is_cursor_agent_binary`
treated any launcher under `PROJECT_DIR` as project-owned, so `scode -C
"$HOME"` refused the launcher at `~/.local/share/cursor-agent/...` — and a
real run canonicalizes `COMMAND[0]` to that path, so every codemux Cursor
run started from home hit it too.

Fix: `_project_dir_is_home` (scode:1722-1734) — the project-owned rule does
not apply when `PROJECT_DIR` is the account home or the effective `$HOME`;
a home-rooted project contains every user-local install, and a launcher
under it is not a project file. Used by `_is_cursor_agent_binary`
(scode:1775) and `_resolved_inside_project` (scode:2150). The header comment
(scode:63-69), `--help` (scode:618-623), the README harness row
(README.md:197), and the CHANGELOG entry (CHANGELOG.md:22-26) state the
exception. Test: `test/07_harness.bats:796` — a home-rooted project with the
launcher stub under `.local/share/cursor-agent` recognizes both spellings;
a normal project still refuses (the sc2/sc7 tests, unchanged).

#### contracts 1 — report section 1 described a state the branch no longer ships

Section 1 still opened the `agent` story with "`KNOWN_HARNESSES` now
contains `agent` ... identical to `cursor-agent`" while section 7 recorded
the opposite, so a reader of section 1 alone carried away the unconditional
rule the final code exists to avoid.

Fix: `docs/align-0.6-report.md:50-75` now states the shipped rule in the
present tense — recognized by resolution, not by name; `KNOWN_HARNESSES`
deliberately omits `agent`; the home-rooted-project exception and the
PATH-prefix rule; recognition equals `cursor-agent` only under those
conditions — and points at section 7 for how the rule got there. Prose
only, no test.

#### contracts 2 — `CODEMUX_*` described as credential-free routing

The README's `--scrub-env` section and the `SCRUB_PATTERNS` comment said
`CODEMUX_*` variables are "how codemux routes a run, not ambient
credentials" in a paragraph framed as listing what carries no secrets —
while section 2 of this report documents `CODEMUX_CODEX_PROVIDER_API_KEY`
as the variable that carries the Codex override API key and deliberately
survives `--scrub-env`.

Fix: every copy now names the exception the way `LLM_API_KEY`'s is named:
`CODEMUX_CODEX_PROVIDER_API_KEY` is credential-shaped, does pass through
`--scrub-env`, and the caller controls it by exporting the override only
for runs that need it — README.md:569, the comment above `SCRUB_PATTERNS`
(scode:228-236), and the unreleased CHANGELOG entry (CHANGELOG.md:60-66).
Prose only, no test.

#### contracts 3 — the guard's comment promised more than the scan delivered

`sh -c "P'A'TH=/tmp/evil; agent"` contains no literal `PATH=`, so the guard
passed while the shell's quote removal made the reassigned PATH the one
that runs; the comment promised "a PATH reassignment anywhere in the
command line" disables recognition, and the code matched only the literal
spellings.

Fix: `_text_reassigns_path` strips quote characters and backslashes before
matching (scode:2160-2170), so the quoted spellings are caught; no benign
command spells an assignment that way. The rewritten comments
(scode:1970-1982, scode:2152-2159) state the actual rule and its limits:
the scan is textual, quotes are normalized, eval and indirection are beyond
it, and over-matching only withholds recognition. Test:
`test/07_harness.bats:818` — `P'A'TH=` and `export P'A'TH=` inside a shell
`-c` string both stay unknown commands.

#### Gates (run in this session, 2026-10-10)

- `make lint` (shellcheck): exit 0.
- `make test-js`: 101 tests, 101 pass, 0 fail, exit 0.
- `make test` under `env -u SCODE_SANDBOXED`: the lint and test-js steps
  pass; the bats step reports 591 tests — 588 ok, 3 not ok — and exits 1 on
  those three. They are the sudo-wrapper preload trio every round since sc1
  has documented: this session's own sandbox forbids `sudo` (`operation not
  permitted`), they fail identically against pristine 0.5.0, and they pass
  in CI. Runtime-sandbox and Linux-only tests skip in this session as
  before.
- Test count vs the pre-sc10 tree: 587 → 591 (+4 new tests;
  `test/07_harness.bats` went from 87 to 91 `@test` blocks). The existing
  sc5/sc7/sc8 guard tests pass unchanged.
- `python ~/.claude/skills/humanizer/scripts/check_american.py` on
  `README.md`, `CHANGELOG.md`, this report, `scode`, and
  `test/07_harness.bats`: exit 0.

## 8. Round sc11: the `agent` recognition removed

The tenth review still found bypasses in the `agent` machinery (`env
-SPATH=bin agent`, `env --unset=PATH agent`) plus contract drift the rule's
own comments could not keep up with. The operator decided to remove the
surface rather than patch it again: `agent` is not a known harness, full
stop, and codemux 0.12.0 launches the Cursor Agent as `cursor-agent` — the
real launcher name, present in every install beside the `agent` symlink —
so nothing is lost.

What was removed from `scode`:

- `_is_cursor_agent_binary`, `_project_dir_is_home`,
  `_resolved_inside_project`, and `_text_reassigns_path` (the sc2, sc9,
  sc7, and sc5/sc10 helpers). `_command_reassigns_path` was already gone
  (sc10).
- The `reassign` flag threaded through `_detect_harness_from_args`,
  `_detect_harness_from_shell_words`, and `detect_harness`, together with
  the PATH-reassignment handling in the `env` branch (`-i`, `-S`, `-u PATH`,
  `-uPATH`, `-P`, `-Pdir`) that existed only to feed it.
- The `agent)` case in `get_harness_config_paths` and the `agent` arm of
  detection.
- `cursor-agent` is back to the plain bare-name rule it had in 0.5.0: no
  project-owned rule, no PATH rule (both were added only for `agent`). A
  diff of the whole detection machinery against pristine 0.5.0 is empty
  except `detect_harness` itself, which keeps the sc10 one-line delegation
  (the second shell `-c` walk that function used to repeat was dead code,
  independent of the `agent` feature).

Everything else from the alignment stands: `agy`, `dsh` documentation, the
scrub patterns, `--keep-env` with its refused list and the Grok-defense
refusal, and the `LLM_API_KEY` scrub.

Tests: nine `agent` tests left `test/07_harness.bats` (the launcher
auto-allow, the sc2 project-owned refusal, and the sc5/sc7/sc8/sc9 guard
tests, one of which covered the `cursor-agent` spelling) and two left
`test/05_environment.bats` (the shortcut pair). One
test stays, rewritten in place of the old "unrelated agent binary" test:
`strict+agent stays an unknown command in dry and real runs`
(`test/07_harness.bats`) — a stub `agent` on PATH warns "not a known
harness" with no `strict+agent`, no `~/.cursor`, and no auto-allow line in
a `--strict --dry-run`, and the same assertions on a real sandboxed run.
The real-run half skips in this session (nested sandbox), as every runtime
test here does; CI runs it.

Docs rewritten to match: the `KNOWN_HARNESSES` header comment, the
`--help` paragraph, the README (the codemux-name table row is gone; a note
after the harness table states that `agent` is not recognized, why, and
that codemux launches `cursor-agent`), and the 0.6.0 CHANGELOG bullet.
Section 1 of this report now states the shipped rule, and section 2 no
longer claims `LLM_API_KEY` stays unscrubbed (round sc4 scrubbed it; the
bullet said otherwise).

### Gates (run in this session, 2026-10-10)

- `make lint` (shellcheck): exit 0.
- `make test-js`: 101 tests, 101 pass, 0 fail, exit 0.
- `bats test/` under `env -u SCODE_SANDBOXED`: 580 tests — 577 ok
  (112 of them this environment's skips: runtime-sandbox and Linux-only),
  3 not ok. The three are the sudo-wrapper preload trio every round since
  sc1 has documented: this session's own sandbox forbids `sudo` (`operation
  not permitted`), they fail identically against pristine 0.5.0, and they
  pass in CI. `make test` therefore exits 1 on those three alone.
- Test count vs the pre-sc11 tree: 591 → 580 (−11: nine removed from
  `test/07_harness.bats`, 91 → 82 `@test` blocks; two removed from
  `test/05_environment.bats`, 53 → 51; the kept test is a rewrite of an
  existing block, so it does not change the count).
- `python ~/.claude/skills/humanizer/scripts/check_american.py` on
  `README.md`, `CHANGELOG.md`, this report, `scode`, `test/07_harness.bats`,
  and `test/05_environment.bats`: exit 0.
