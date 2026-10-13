# Harness detection and authentication

Recognition selects state paths. It does not certify a vendor's authentication
flow, runtime compatibility, or safety. Unknown commands can run with a warning.

## Detection and state

The command executable is resolved and canonicalized before detection.
A trailing `.exe` is ignored for harness recognition. Supported transparent
wrappers include `env`, `nice`, `timeout`, `command`, `stdbuf`, `ionice`,
`taskset`, and shell `-c` forms. Parsing is conservative, not full shell
evaluation. An argument such as `echo claude` does not select Claude state.

A standalone executable named `agent` is unknown. An executable symlink named
`agent` resolving to `cursor-agent` is recognized by its canonical name.
Detection of names inside wrapper text does not establish binary identity.
Shell aliases are interactive conveniences and do not enforce sandbox use.

Strict mode automatically grants these paths read-write access:

| Command | Paths under effective HOME |
|---|---|
| `opencode` | `~/.config/opencode`, `~/.local/share/opencode` |
| `claude` | `~/.claude` |
| `codex` | `~/.codex` |
| `goose` | `~/.config/goose` |
| `gemini`, `agy` | `~/.gemini` |
| `droid` | `~/.factory` |
| `qwen` | `~/.qwen` |
| `codemux` | `~/.codemux`, `~/.config/codemux` |
| `pi` | `~/.pi/agent` |
| `aider` | `~/.aider`, `~/.aider.conf.yml` |
| `amp` | `~/.config/amp`, `~/.amp` |
| `crush` | `~/.config/crush`, `~/.local/share/crush` |
| `cursor-agent` | `~/.cursor` |
| `copilot` | `~/.copilot`, `~/.cache/copilot` |
| `cn` | `~/.continue` |
| `kimi` | `~/.kimi-code`, `~/.kimi` |
| `openhands` | `~/.openhands` |
| `cline` | `~/.cline` |
| `kiro-cli` | `~/.kiro` |
| `auggie` | `~/.augment` |
| `grok` | `~/.grok` |

These grants are disabled by `--trust untrusted` and suppressed by custom blocks.
Symlinks resolving outside HOME are ignored. Linux binds only existing state
paths. macOS rules can permit creation of state within the named subtree.
Environment-selected roots such as `GROK_HOME` are not automatically granted;
use an explicit allow for a reviewed custom location.

Copilot's `~/.cache/copilot` grant is cross-platform. Its macOS primary cache
under `~/Library/Caches/copilot` remains blocked unless explicitly allowed.
No broad macOS Library grant is added for any harness.
DeepSeek Harness (`dsh`) has no verified state-path entry.

Writable state lets harnesses persist settings and rotated OAuth credentials.
Every program launched within that sandbox can potentially read those
credentials. State access also permits modification. See [policy](policy.md)
for project and explicit-grant exceptions.

## Claude Code on macOS

Claude's macOS subscription login can live in Keychain, hidden by the
`~/Library` block. For an eligible direct launch, scode copies usable Keychain
access credentials into `~/.claude/.credentials.json`. The copied OAuth object
has an empty `refreshToken` and no `refreshTokenExpiresAt`. Other top-level
file state is preserved. The destination is replaced atomically with mode 0600.
The state directory must already exist. If the `security` command is
unavailable, synchronization and its mirrored-token checks are skipped.

This avoids duplicate refresh-token rotation. It still exposes a bearer token
to anything able to read the file. Authentication lasts only as long as that
token remains usable; expiration or revocation can produce an authentication
error. scode does not promise a particular vendor error message.

The access-only guarantee applies to successfully synchronized macOS
Keychain-backed credentials. Linux bypasses synchronization. A macOS file-only
login with no Keychain item is preserved, including its refresh token.
Independent environment or application authentication can also remain available.

| Condition | Action |
|---|---|
| Eligible direct installed Claude, readable usable Keychain token | Copy access credential unless file already matches without a refresh token |
| Expired/unusable Keychain token, mirrored file has refresh token | Preserve file's access data but remove refresh token after backup |
| No usable token and file already lacks refresh token | Leave file alone |
| No Keychain item (status 44) | Preserve file-only store |
| Keychain locked/denied, file has mirrored refresh token | Refuse launch |
| Rewrite or required backup fails with mirrored refresh token present | Refuse launch |
| `--no-credential-sync` | Skip copying; refuse an accessible mirrored refresh token when detected |
| Wrapper, in-project Claude binary, in-project state directory, or symlinked credential path | Skip copying, warn; refuse if the mirrored-refresh-token check finds one |
| Dry-run, blocked credential, or untrusted preset without an explicit state grant | Skip copying |
| Untrusted preset with explicit state grant | Skip copying; check mirrored-refresh-token refusal |

Opting out disables the copy, not authentication. Existing access-only files,
file-only credentials, or independently supplied authentication may work.
Synchronization does not rewrite through a symlink; refusal checks may read its
target. These checks need working system Python. If Python cannot inspect the
file, it cannot establish that the file lacks a refresh token.

The untrusted preset's refusal guard checks explicit grants, not every route
through project selection. Do not select the credential directory itself as an
untrusted project. General reachability analysis and reliable credential
inspection failure handling remain deferred.

## Backup retention and recovery

Before stripping a mirrored refresh token, scode backs up the old file to
`~/Library/Application Support/scode/credential-backups/credentials.*`.
The directory is mode 0700 and files are mode 0600. Successful rewrites prune
strictly older backups, leaving the current backup and any newer concurrent
backup. Failed rewrites remove their new backup because the original remains.
The warning reports the relevant random filename; use its modification time
and that warning to identify it.

The default Library block hides backups, but an explicit allow or project grant
can expose them. Keep them outside the sandbox's reachable paths. For recovery,
stop sandboxed Claude runs, preserve the relevant backup privately, and prefer
a fresh Claude login outside scode. Restoring a refresh token may restore a
revoked or rotated credential. If an operator must restore the file, do so
outside the sandbox after checking which store is authoritative; the next sync
can strip it again. Do not print tokens into logs or commit backups.

## Antigravity

The 2026-10-12 integration observation recorded macOS Antigravity using a
generic-password Keychain item through go-keyring and `/usr/bin/security`,
rather than a file credential store. The v1.3.1 state-path inspection identified
`~/.gemini/antigravity-cli`, shared `~/.gemini/config`, and root state files.
A help command that writes no files proves only that help invocation's behavior.

Ordinary scode invocation does not provide an Antigravity credential mirror.
Recognizing `agy` and granting `~/.gemini` therefore does not make its macOS
Keychain login available. The integration note recorded codemux supplying a
private per-run mirror Keychain; verify that behavior against the installed
codemux version. Do not grant all of `~/Library/Keychains`: access through
`security` can expose unrelated items and refresh tokens.
