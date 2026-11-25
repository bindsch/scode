# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.10] - 2026-11-25

### Fixed

- macOS: 0.6.9 denied `com.apple.SecurityServer` to every sandbox without the
  applied login-store grant. Programs that load the system root certificates
  through the keychain API (Codex, and anything built on `rustls-native-certs`)
  open the certificate keychains through that service, so every HTTPS request
  they made inside the sandbox failed ("error sending request"). 0.6.10 leaves
  `com.apple.SecurityServer` reachable.

### Security

- The final Mach deny names `com.apple.authd`, `com.apple.security.agent`,
  `com.apple.security.agent.login`, `com.apple.security.authhost`, and
  `com.apple.securityd.xpc`. The dialog for a missing default keychain is
  requested through an authorization session, which only `com.apple.authd`
  makes; with it denied, `AuthorizationCreate` fails inside the sandbox.
  securityd itself can still ask about a keychain file the sandbox can read
  (see `docs/security.md`).
- The profile now ends with a deny of the login keychain directories
  (`~/Library/Keychains` under the run's HOME and under the account home) and
  of every user keychain the preference file records as the default, the login
  keychain or in the search list, each by every name its links give it. It is
  the last file rule, so those keychain files and the daemon that decrypts
  their items are never in the same sandbox without the login-store grant. A
  path that cannot be resolved with certainty stops the launch.

### Changed

- `--allow "$HOME/Library/Keychains"` (or an `allowed:` entry, or a project
  directory there) no longer gives the keychain files without the applied
  login-store grant: the final deny overrides it. Use `--login-store` with an
  eligible `claude` or `agy` launch.

## [0.6.9] - 2026-11-24

**Correction:** this release denied `com.apple.SecurityServer` in every
configuration without the applied login-store grant, which broke HTTPS for programs that load the system root
certificates through the keychain API. It is withdrawn; use 0.6.10.

### Security

- macOS: a sandboxed process can no longer cause a keychain or authorization
  dialog through its own calls unless keychain access was granted. Work it
  hands to a process outside the sandbox is not covered (see "Limits" in
  `docs/security.md`). Until now the keychain was
  protected by file rules only, and `com.apple.SecurityServer` and
  `com.apple.authd` stayed reachable. A store from a sandbox that could not see
  `~/Library/Keychains` made macOS show "A keychain cannot be found to store ...".
  One launcher decision now yields both the login-store file grant and a final
  `(deny mach-lookup ...)` rule for `com.apple.SecurityServer`,
  `com.apple.securityd.xpc`, `com.apple.authd`, `com.apple.security.agent`,
  `com.apple.security.agent.login`, and `com.apple.security.authhost`. The deny
  is emitted for every command in normal and strict modes unless the
  `--login-store` grant is applied and `~/Library/Keychains/login.keychain-db`
  exists under the sandbox HOME.

### Changed

- The login-store grant is declined, with a reason, when
  `~/Library/Keychains/login.keychain-db` does not exist as a regular file inside
  that directory after links are resolved. This includes a private HOME with no
  login keychain. Previously the directory was granted anyway.
- The grant is also declined when `com.apple.security.plist` records a default
  keychain that is outside `~/Library/Keychains` or does not exist. The same
  holds for a recorded login keychain, and for a preference file that cannot
  be read.
- Without the applied grant, keychain and authorization calls from the sandbox
  fail with an error and no dialog: `security` subcommands, keyring libraries,
  `git-credential-osxkeychain`, keychain-held signing identities and client
  certificates. TLS trust evaluation goes through `com.apple.trustd` and still
  works for the clients checked (see `docs/security.md`).
- `--allow "$HOME/Library/Keychains"` without the login-store grant still grants
  the files but no longer leaves the keychain services reachable. Use
  `--login-store` with an eligible `claude` or `agy` launch for keychain access.
- Linux behavior is unchanged.

### Fixed

- `--log`: a signal that ended scode right after the log writer was started
  could leave that writer waiting forever in its pipe open, holding the
  caller's output descriptors. scode now opens the pipe first, so the writer's
  open never waits and the writer exits as soon as scode is gone.

## [0.6.8] - 2026-11-16

### Added

- Repeatable macOS `--allow-staged PATH` and user-config `allowed_staged:`
  grant read-write access to the base file and its `.tmp.` siblings
  with eight hexadecimal digits. The macOS kernel ignores letter case across the
  whole staged path, including directory and base names, even on case-sensitive
  volumes. Symlinked base files are refused. Atomic replacement works in normal
  and strict modes without granting directory listings. CLI block precedence,
  untrusted explicit-grant rules, and read-only caps remain in force. Linux
  rejects these grants because bind mounts cannot express the filename bound.
- `--login-store` and user-config `login_store: true` opt in to macOS login-store
  access, which is off by default. `--no-login-store` and user/project
  `no_login_store: true` suppress it even after opt-in, regardless of flag order.
  Project config cannot enable it; overlapping custom blocks and
  `--trust untrusted` suppress the whole grant.

### Changed

- Removed Claude credential synchronization, Keychain queries, mirror writes,
  refresh-token scrubbing and refusals, and credential backup creation and
  pruning. Existing mirror files and backups are left alone. scode never
  reads, copies, changes, or checks a harness login.
- With login-store access enabled, normal and strict macOS `claude` and `agy`
  runs receive read-write access to `~/Library/Keychains` so the harness can
  refresh its own item, and read-only access to
  `~/Library/Preferences/com.apple.security.plist` when present. The invoked
  harness name must resolve to a regular executable outside the project; native
  version-number targets and Homebrew `.exe` targets qualify. Interpreter entry
  scripts and shell `-c` wrappers do not. Both modes report grants or declines.
  Every process in an enabled sandbox can read Keychain items whose access list
  trusts `/usr/bin/security` without a dialog, including the harness login with
  its refresh token and tokens stored by other tools. It can read and copy out
  `login.keychain-db`, encrypted under the account's login password, which can
  then be attacked offline. It can create, modify or delete files in the keychain
  directory. It cannot change the default keychain or search list through the
  read-only preference file. See `docs/security.md` for manual-grant precedence.
- Without the grant, a sandboxed `claude` on macOS falls back to
  `~/.claude/.credentials.json` if one exists and is accessible. scode does not
  inspect that file and cannot create a stale refresh-token copy; existing copies
  and backups remain untouched.
- `--no-credential-sync` remains accepted as a documented no-op for this release.

### Upgrade note

0.6.7 scrubbed or refused a `~/.claude/.credentials.json` that held a refresh token.
0.6.8 never inspects that file. If you have one from an older file login, after
confirming that your Keychain login works, remove the file yourself.
scode prints nothing about login state.

### Tests

- Staged grants are checked under the real macOS sandbox in normal and strict
  modes: atomic replacement works, and names that are not eight hexadecimal
  digits, other base names except case variants, and directory listings stay denied.
- Synthetic macOS kernel tests verify preference reads, denied writes and
  replacements, and denied creation when absent, with login-store access enabled.
- Replaced credential-copy tests with an offline no-Keychain gate using fake
  harnesses, a fake `security`, static launcher checks, and policy assertions.
- Added a regression check that empty environment values survive
  `--scrub-env` and `--keep-env` when the variable is retained.

## [0.6.7] - 2026-11-14

### Added

- Repeatable `--allow-ro PATH` and user-config `allowed_ro:` grants reopen
  reads and execution inside blocked stores without granting writes. They
  work in strict mode, resolve like `--allow`, and appear in dry-run output.
  CLI blocks override config grants; project config cannot add authority.
  Read-only grants cap overlapping writable grants on both backends.
  Nested blocks remain enforced; missing read-only paths are refused.
  JSON and legacy log headers record these grants as `allowed_ro`.

### Fixed

- macOS strict runs sweep detached descendants at exit using a protected
  per-run Seatbelt permission marker and generation-checked signals. Cleanup
  sends TERM, waits one second, then KILL, preserving unrelated processes and
  the command status. Startup probes verify identity and signaling support;
  unavailable support warns that descendants may survive. macOS 27.2 runtime
  tests cover double fork, setsid, TERM resistance, logging, interruption, and
  concurrent runs. The sweep runs with INT, TERM, HUP, and QUIT ignored, so a
  second interrupt at exit cannot abort it. This remains bounded cleanup, not a
  kernel lifetime boundary.

## [0.6.6] - 2026-11-10

### Fixed

- A temporary preload alias under a retained custom block now refuses launch
  before creating the link. Space-containing installations can no longer
  bypass `--block /tmp`. The reference model also distinguishes custom block
  targets from their written symlink names when applying allows.
- Selecting a project inside a built-in block now exempts only that project.
  Strict mode keeps sibling credentials blocked when automatic harness state
  exposes the parent, including when the built-in block is a symlink.
- Strict mode now applies built-in blocks inside granted paths on macOS and
  Linux. It emitted no rule for them, so a grant that covered one reopened it:
  `scode --strict -C ~` left `~/.ssh` and `~/.config/gh` readable, and
  `~/Library` on macOS. A built-in block with any spelling inside the project, an
  explicit allow, or detected harness state, including a link that resolves
  into the grant or a system read grant, is now denied after the grant on
  macOS and masked after the bind on Linux. An explicit allow still lifts a
  block, an allowed child of a block is granted again after it, and a project
  that is itself a built-in block is granted as in default mode.
- Linux strict mode masks custom blocks inside detected harness state. They
  were masked only inside the project or an explicit allow, so
  `--block ~/.codex/private` stayed readable under `scode --strict codex`.
- On macOS a child allow that the final guards restore can no longer reopen a
  built-in block inside it. Every re-denial preserves the project exception,
  including when an intermediate symlink lies inside that child allow.
- macOS block predicates preserve explicit child exceptions at every emission,
  including a separately allowed target file reached through an intermediate
  link inside a restored allow. Repeated denials cannot revoke that exception.
- Linux command and preload read exceptions no longer revoke an existing
  writable grant. Exact read-only binds are added only when earlier mounts
  hide the file. A generated reference-model suite checks both backends.
- macOS strict mode applies built-in blocks within its private temp grant.
- Linux project restoration checks only canonical mask targets, so a built-in
  link inside the project cannot remask the project itself or its parent.
- Linux strict mode also enforces custom blocks inside system read grants.
- Automatic harness state grants no longer reopen built-in blocked parents,
  including through symlinks. Explicit allows and project selection keep
  their existing precedence.
- Linux read-only project binds now follow ancestor grant restorations and
  precede the final masks. Previously the last project bind reopened blocked
  children in both modes. Restoring an allowed ancestor cannot override `--ro`.
- Exact read-only Node preload exceptions now follow built-in blocks on both
  platforms, including linked and space-containing installation paths. Node
  can start when scode is installed under a blocked directory without exposing
  sibling files. Custom preload blocks still disable injection.
- Linux command exceptions now compare resolved built-in block targets, so a
  linked blocked directory does not hide the exact command executable.

## [0.6.5] - 2026-11-10

### Fixed

- macOS blocks now cover the resolved target of a symbolic link. Seatbelt
  matches the path the kernel resolved, and the profile named only the link,
  so with `~/.aws` linked to `~/dotfiles/aws`, `cat ~/dotfiles/aws/credentials`
  printed the secret inside the sandbox; a block under a linked ancestor such
  as `~/.config/gh` was readable even through its own name. Every deny rule
  now lists the link name, each path met while links resolve, and the
  canonical target. Dangling links are denied at their target path and link
  cycles under every name. Custom blocks keep the name the user wrote as well
  as the canonical path.
- On macOS a later grant (the project override, a `~/Library` carve-out, or a
  child allow) is followed by a deny for every block spelling inside it, so it
  cannot reopen a block's resolved target. The project, preload, and command
  binary checks compare every spelling of a block.
- An allow of a built-in block's link name, or of its resolved target, lifts
  that block on macOS and Linux. Allows are canonical and built-in blocks are
  not, so `--allow ~/.aws` used to leave the block in place, which Linux 0.6.4
  then enforced at the resolved target.

## [0.6.4] - 2026-11-10

### Fixed

- Linux sandboxes start on Ubuntu 26.04. There `/usr/bin/sudo` is an absolute
  link to sudo-rs through `/etc/alternatives`, and the privilege mask
  `--ro-bind /dev/null /usr/bin/sudo` made bubblewrap fail with "Can't create
  file at /usr/bin/sudo", so every Linux run failed. Masks and blocks are now
  mounted on the path with every symbolic link resolved, which bubblewrap
  accepts and which covers every name that leads to the target. The same fix
  applies to default blocks that are links or sit under a linked directory
  (a dotfile manager's `~/.aws` or `~/.config`): they also failed to start
  before. A missing privilege tool or a dangling link to one is skipped.
- Linux also masks the classic `sudo.ws` and the sudo-rs names (`sudo-rs`,
  `su-rs`, `sudoedit`, `sudoedit-rs`, and the binaries in `/usr/lib/cargo/bin`), so a host with
  both sudo implementations installed exposes neither.
- A block whose link resolves into the project, or into a strict-mode grant,
  is reasserted after the project bind; an allowed child of a linked block is
  rebound after the block's resolved target.

## [0.6.3] - 2026-11-09

### Fixed

- macOS strict profiles now permit metadata-only reads of the home and of
  every ancestor directory of a granted path. A real Codex session previously
  failed at startup to initialize its sqlite state runtime under `~/.codex`
  even though that directory was granted read-write: canonicalizing the path
  stats each ancestor, and those stats were denied.

### Development

- Dev dependencies pin glob 14.0.4 and minimatch 11.0.5 through npm overrides, clearing the
  moderate advisories in c8's test-exclude chain so `npm audit --audit-level=low` passes again.

## [0.6.2] - 2026-10-28

### Fixed

- Recognize resolved Copilot, pi, Claude Code, and Codex package entry scripts
  by their `node_modules` directories so strict mode applies their state grants.
  Keep basename detection and `.exe` launcher support.
  Entry scripts are detected for their state directories, but credential sync
  requires the harness launcher binary because a script's interpreter comes
  from the caller's PATH.

### Documentation

- Describe Cursor Agent's macOS Keychain login (`cursor-access-token`, `cursor-refresh-token`, `cursor-api-key`), why the `~/Library` block hides it, and the supported `AGENT_CLI_CREDENTIAL_STORE=file` login that writes `~/.cursor/auth.json` ([harnesses](docs/harnesses.md)).

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
