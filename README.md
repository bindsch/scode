# scode

> **Beta software (v0.1.1).** This is under active development. Defaults may change, features may break, and sandbox coverage is not guaranteed to be complete. Use at your own risk. Pull requests welcome.

scode wraps AI coding tools (Claude, Codex, OpenCode, etc.) in an OS-level sandbox that prevents them from reading or modifying personal files, credentials, and sensitive directories. One policy, all agents, zero infrastructure.

## Quickstart

```bash
brew install bindsch/tap/scode   # macOS; Linux: sudo apt install bubblewrap, then install from source
scode claude                     # sandbox claude (project dir accessible, personal files blocked)
scode codex                      # same policy, different harness — works with any agent
scode --strict opencode          # deny-default sandbox — only essentials allowed
scode --trust untrusted goose    # maximum lockdown: strict + no-net + read-only + scrub env
```

Never run unsandboxed by accident:

```bash
alias claude='scode claude'      # add to ~/.bashrc or ~/.zshrc
```

## Why scode

AI coding CLIs are starting to ship built-in sandboxes. A few third-party wrappers exist. Why another tool?

**One policy, all agents.** scode is agent-agnostic. One config, one set of rules, consistent across Claude, Codex, OpenCode, Goose, Gemini, or anything else you run. Audit one boundary, not five.

**Zero infrastructure.** Single bash script. No daemon, no proxy, no container, no language runtime. Works on a fresh macOS machine with nothing installed, or any Linux box with bubblewrap.

**Batteries included.** Blocks credentials, cloud tokens, password managers, and personal files across 20+ paths out of the box (35+ on Linux with platform-specific extras). Chromium double-sandbox issues handled automatically. Environment scrubbing strips 30 token patterns (including wildcards like `AWS_*`).

**YOLO mode safety net.** Running with `--dangerously-skip-permissions` or auto-accepting tool calls? scode lets you do that without less worry. The harness can write code and run commands freely inside your project, but it still cannot touch your cloud credentials, password managers, or personal documents. Accept permissions more liberally knowing the blast radius is capped.

**Config-driven profiles.** YAML configs let you maintain separate security postures — daily driver, paranoid review, cloud engineering — and switch with `--config`.

## How it works

scode generates a sandbox profile and runs your command inside it. Two modes:

- **Default mode** (allow-default): everything is allowed, then specific sensitive directories are denied.
- **Strict mode** (`--strict`): everything is denied, then only the essentials are allowed.

Default mode is practical for daily use and intentionally not deny-all. If you want deny-default behavior, use `--strict` (or `--trust untrusted` for strict + no-net + scrub-env + read-only).

## Installation

### Homebrew (macOS)

```bash
brew install bindsch/tap/scode
```

### From source

```bash
git clone https://github.com/bindsch/scode.git
cd scode
sudo make install
```

Install to a different prefix (no sudo needed):

```bash
make install PREFIX=~/.local
```

Uninstall:

```bash
sudo make uninstall
```

If you installed with a custom prefix, use the same prefix for uninstall:

```bash
make uninstall PREFIX=~/.local
```

### Manual

```bash
VERSION="vX.Y.Z"  # set to the release tag you want, e.g. v0.1.1
curl -fsSL "https://raw.githubusercontent.com/bindsch/scode/${VERSION}/scode" -o /usr/local/bin/scode
chmod +x /usr/local/bin/scode
mkdir -p /usr/local/lib/scode
curl -fsSL "https://raw.githubusercontent.com/bindsch/scode/${VERSION}/lib/no-sandbox.js" -o /usr/local/lib/scode/no-sandbox.js
```

### Linux prerequisite

```bash
# Debian/Ubuntu
sudo apt install bubblewrap

# Fedora/RHEL
sudo dnf install bubblewrap
```

## Usage

```
scode [options] [--] <command> [args...]
scode [options] <harness> [args...]
scode audit [--watch|-w] <logfile>
```

If no command is provided, `scode` defaults to `opencode`.

### Options

| Flag | Description |
|------|-------------|
| `-h, --help` | Show help |
| `-V, --version` | Show version |
| `-n, --no-net` | Disable network access |
| `-C, --cwd DIR` | Set project/working directory (default: `$PWD`; singleton) |
| `--ro` | Mount project directory read-only |
| `--rw` | Mount project directory read-write (default) |
| `--block PATH` | Block access to a path — directory or file (repeatable) |
| `--allow PATH` | Allow a path subtree, overriding block rules (repeatable) |
| `--strict` | Deny-default sandbox |
| `--trust LEVEL` | Named trust preset: `trusted`, `standard`, `untrusted` (singleton) |
| `--config FILE` | Use a specific config file (default: `~/.config/scode/sandbox.yaml`; singleton) |
| `--scrub-env` | Strip API keys and tokens from environment |
| `--log FILE` | Log sandbox violations to the specified file (creates parent directories if needed; singleton) |
| `--dry-run` | Print sandbox profile without executing |
| `audit --watch`, `audit -w` | Tail an audit log and print new denials in real time |

`--block` / `--allow` (and config `blocked` / `allowed`) treat relative paths as project-relative, using `--cwd` when set. `allowed` is recursive (firewall-style): allowing `/a` allows `/a/**`, even if descendants are in defaults or `blocked`.

On Linux in default mode, `--allow` under a blocked parent requires the allowed path to already exist so bubblewrap can re-bind it. If it does not exist yet, scode warns and cannot apply that override until you create the path.

Flags marked **(singleton)** can only be specified once. Passing them twice is an error. Repeatable flags (`--block`, `--allow`) accumulate.

### Examples

```bash
scode claude                       # run claude in sandbox
scode codex                        # same rules, different harness
scode -- npm test                  # run any command in sandbox
scode --ro opencode                # read-only project directory
scode --allow ~/Documents claude   # unblock a default-blocked dir
scode -n goose                     # no network access
scode --strict claude              # deny-default; auto-allows ~/.claude + macOS Library
scode --trust untrusted codex      # maximum lockdown (strict + no-net + scrub + ro)
scode --trust trusted gemini       # minimal sandbox (rw, net on)
scode --scrub-env claude           # strip API keys from env
scode --config examples/sandbox-paranoid.yaml opencode  # use a specific config
scode --log session.log codex      # log denials for review
scode audit session.log            # parse denials, suggest --allow flags
scode audit --watch session.log    # live-tail denials in real-time
```

### Known harnesses

These commands are recognized without needing `--`:

`opencode`, `claude`, `codex`, `goose`, `gemini`, `droid`, `qwen`, `codemux`, `pi`

Unknown commands still run but produce a warning that sandbox behavior has not been tested.

### Environment variables

| Variable | Values | Default |
|----------|--------|---------|
| `SCODE_CONFIG` | Path to config file | `~/.config/scode/sandbox.yaml` |
| `SCODE_NET` | `on`, `off` | `on` |
| `SCODE_FS_MODE` | `rw`, `ro` | `rw` |

## Trust presets

Named presets combine common flags into a single `--trust` level:

| Preset | Equivalent to | Use case |
|--------|---------------|----------|
| `trusted` | `--rw`, net on, no strict, no scrub | Trusted projects — minimal sandbox |
| `standard` | *(no flags)* | Default behavior |
| `untrusted` | `--strict --no-net --scrub-env --ro` | Untrusted code review — maximum lockdown |

Trust presets override config-file settings for the values they control. `--trust untrusted` cannot be weakened by a config's `net: on` or `strict: false`. Explicit CLI flags (`--rw`, `--strict`, etc.) override `--trust` settings.

If the default allow-first posture is too permissive for your use case, start with `--trust untrusted`.

### Hardening quickstart (untrusted tasks)

For untrusted code review or unknown tools, use the `untrusted` trust preset:

```bash
scode --trust untrusted goose
```

This is equivalent to:

```bash
scode --strict --no-net --scrub-env --ro goose
```

For further hardening, add explicit blocks:

```bash
scode --trust untrusted --block ~/.ssh codex
```

Use Linux equivalents where paths differ.

**Harness auto-allow:** When `--strict` detects a known harness as the command binary (or behind transparent wrappers such as `env`, `nice`, `timeout`, `command`, `stdbuf`, `ionice`, `taskset`, or shell `-c` wrappers), it automatically allows:

- The harness config directory (e.g. `~/.claude` for claude, `~/.config/opencode` for opencode)
- macOS `~/Library` browser carve-outs (`Application Support`, `Caches`, `Preferences`, `Saved Application State`) — read-write
- macOS `~/Library/Keychains` — read-only

This means `scode --strict claude` works out of the box. No manual `--allow` flags needed for the harness itself.

Detection is conservative: only the command binary (or the binary behind supported transparent wrappers) triggers auto-allow. Harness names appearing as arguments do not — `scode --strict -- echo claude` does not auto-allow `~/.claude`.

To suppress a specific auto-allow, use `--block`:

```bash
scode --strict --block ~/Library/Keychains claude
```

For unknown commands or additional paths, add `--allow` manually:

```bash
scode --strict --allow ~/.ssh -- npm test
```

If an `--allow` path does not exist in strict mode, scode warns and does **not** create it. Create the directory yourself first.

> **Linux strict note:** `XDG_RUNTIME_DIR` (typically `/run/user/$UID`) is intentionally not bound.
> It contains sockets (Wayland, PulseAudio, D-Bus) that expand attack surface. If a tool
> needs it, add `--allow /run/user/$UID` explicitly.

## Configuration

Optional config file at `~/.config/scode/sandbox.yaml`. Entries are merged with built-in defaults:

- `blocked:` adds to the default blocked list
- `allowed:` overrides blocks recursively (the path and all descendants), including defaults and your additions
- Scalar options (`net`, `fs_mode`, `strict`, `scrub_env`) set defaults that CLI flags can override

### Project config

A `.scode.yaml` file in the project root (the `--cwd` directory) is loaded with lower priority than the user config. Same format. This lets you ship per-project sandbox policies:

```yaml
# .scode.yaml — project-specific sandbox config
strict: true
blocked:
  - ~/Dropbox
allowed:
  - ./data    # relative to project dir
```

Priority: CLI flags > user config (`~/.config/scode/sandbox.yaml`) > project config (`.scode.yaml`) > environment variables > built-in defaults. This priority is strict: user config `strict: false` overrides project config `strict: true`, and user config `net: off` overrides project config `net: on`.

**Security note:** Project configs are untrusted by default. If a `.scode.yaml` `allowed:` entry would unblock a default-protected path (e.g. `~/Documents`, `~/.aws`), scode emits a warning to the terminal. This makes it visible when a cloned repo tries to weaken your sandbox. User config and CLI flags always take precedence.

```yaml
# Sandbox flags (act as defaults; CLI flags always win)
strict: true
scrub_env: true
# net: off           # disable network
# fs_mode: ro        # read-only project dir

# Block additional directories
blocked:
  - ~/Dropbox
  - ~/OneDrive

# Allow specific directories, overriding defaults
allowed:
  - ~/Documents/projects
```

| Config key | Values | Equivalent CLI flag |
|------------|--------|---------------------|
| `net` | `on`, `off` | `--no-net` |
| `fs_mode` | `rw`, `ro` | `--ro` / `--rw` |
| `strict` | `true`, `false` | `--strict` |
| `scrub_env` | `true`, `false` | `--scrub-env` |

### Example configs

Copy any of these to `~/.config/scode/sandbox.yaml`, or use them with `--config`.

From a repo checkout:

```bash
scode --config examples/sandbox-paranoid.yaml codex
```

From an installed package:

```bash
# Homebrew
scode --config "$(brew --prefix)/share/scode/examples/sandbox-paranoid.yaml" gemini

# make install PREFIX=/usr/local (default)
scode --config /usr/local/share/scode/examples/sandbox-paranoid.yaml opencode
```

Manual install of just `scode` + `no-sandbox.js` does not include examples; use the repo files directly or download them from GitHub.

| File | Use case |
|------|----------|
| [`sandbox.yaml`](examples/sandbox.yaml) | Base template with commented-out common additions |
| [`sandbox-strict.yaml`](examples/sandbox-strict.yaml) | Strict mode with extra blocked directories |
| [`sandbox-paranoid.yaml`](examples/sandbox-paranoid.yaml) | Maximum lockdown for untrusted code review |
| [`sandbox-permissive.yaml`](examples/sandbox-permissive.yaml) | Opens up dirs for trusted projects (docs, datasets) |
| [`sandbox-cloud-eng.yaml`](examples/sandbox-cloud-eng.yaml) | Cloud/infra engineers: allows kubectl/Docker/Helm config dirs |

## Default protections

### Directories blocked on all platforms

**Personal files:**

| Directory | Reason |
|-----------|--------|
| `~/Documents` | Personal documents |
| `~/Desktop` | Desktop files |
| `~/Pictures` | Photos |
| `~/Downloads` | Downloaded files |

**Cloud credentials:**

| Directory | Reason |
|-----------|--------|
| `~/.aws` | AWS credentials and config |
| `~/.azure` | Azure CLI tokens |
| `~/.config/gcloud` | Google Cloud credentials |
| `~/.kube` | Kubernetes config |
| `~/.docker` | Docker registry auth |

**Cryptographic keys and password managers:**

| Directory | Reason |
|-----------|--------|
| `~/.gnupg` | GPG private keys |
| `~/.1password` | 1Password data |
| `~/.op` | 1Password CLI tokens |
| `~/.password-store` | `pass` password store |

**Auth tokens:**

| Directory | Reason |
|-----------|--------|
| `~/.npmrc` | npm registry tokens |
| `~/.netrc` | Generic credentials (curl, git, heroku) |
| `~/.git-credentials` | Git credential store |
| `~/.pypirc` | PyPI registry tokens |
| `~/.gem/credentials` | RubyGems API key |
| `~/.cargo/credentials.toml` | Cargo/crates.io token |
| `~/.config/gh` | GitHub CLI tokens |
| `~/.config/hub` | Hub CLI tokens |

### What is NOT blocked

- **`~/.ssh`** -- SSH keys are needed for git operations. Not blocked by default. Use `--block ~/.ssh` if you want to block it.
- **Your project directory** -- full read-write access (or read-only with `--ro`).
- **Network** -- fully open by default (disable with `-n`).
- **`~/.claude`**, **`~/.config`** (except gcloud/gh/hub; Linux also blocks additional subdirs — see below), **`~/.local`** (except Linux keyrings), **`~/.cargo`** (except credentials.toml), etc.
- All system paths (`/usr`, `/bin`, `/System`, etc.) and temp directories.

If you do not want this allow-first baseline, use strict mode: `scode --strict ...` or `scode --trust untrusted ...`.

### macOS: ~/Library

`~/Library` is blocked wholesale, with specific carve-outs:

**Read-write** (browsers/tools need these):

| Subdirectory | Reason |
|---|---|
| `~/Library/Application Support` | Browser profiles (Chrome, Brave, Edge) |
| `~/Library/Caches` | Browser and tool caches |
| `~/Library/Preferences` | plist config files |
| `~/Library/Saved Application State` | Window restore |

**Read-only** (tools can read, sandbox cannot modify):

| Subdirectory | Reason |
|---|---|
| `~/Library/Keychains` | Auth tokens (e.g. Claude's OAuth). Read-only so nothing in the sandbox can modify your keychain. |

Everything else in `~/Library` (Mail, Messages, Cookies, Safari, Contacts, Photos, etc.) is denied. New or unknown subdirectories are blocked by default.

To fully unblock: `scode --allow ~/Library opencode`

### Linux: additional blocks

On Linux, scode blocks additional directories beyond the cross-platform defaults:

| Category | Directories |
|---|---|
| Cloud credentials | `~/.config/doctl`, `~/.config/helm`, `~/.terraform.d` |
| Password managers / keyrings | `~/.config/Bitwarden CLI`, `~/.config/Bitwarden`, `~/.local/share/keyrings`, `~/.local/share/kwalletd` |
| Auth tokens | `~/.config/pip`, `~/.config/git/credentials` |
| Browser profiles | `~/.mozilla`, `~/.config/google-chrome`, `~/.config/chromium`, `~/.config/BraveSoftware` |
| Email / messaging | `~/.thunderbird`, `~/.config/Signal` |
| Personal files | `~/Videos` |
| App sandboxes | `~/.var/app` (Flatpak), `~/snap` |

### Always blocked (both modes)

- `/usr/bin/sudo`, `/usr/bin/su`, `/usr/bin/login`, `/usr/bin/doas`, `/usr/bin/pkexec` -- privilege escalation prevention

## `--scrub-env`

When enabled, strips these environment variables before the command runs (not on by default):

`AWS_*`, `AZURE_*`, `GOOGLE_APPLICATION_CREDENTIALS`, `DO_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `HF_TOKEN`, `HUGGING_FACE_HUB_TOKEN`, `COHERE_API_KEY`, `MISTRAL_API_KEY`, `REPLICATE_API_TOKEN`, `TOGETHER_API_KEY`, `GROQ_API_KEY`, `FIREWORKS_API_KEY`, `DEEPSEEK_API_KEY`, `GITHUB_TOKEN`, `GH_TOKEN`, `GITLAB_*_TOKEN`, `VERCEL_TOKEN`, `NETLIFY_AUTH_TOKEN`, `VAULT_TOKEN`, `PULUMI_ACCESS_TOKEN`, `CLOUDFLARE_API_TOKEN`, `SENTRY_AUTH_TOKEN`, `SNYK_TOKEN`, `NPM_TOKEN`, `DOCKER_PASSWORD`, `DOCKER_AUTH_CONFIG`, `SSH_AUTH_SOCK`, `SSH_AGENT_PID`

## `scode audit`

After a session with `--log`, use `scode audit` to parse the denial log and get suggested `--allow` flags:

```bash
scode --log session.log --strict opencode
# ... work in the sandbox ...
scode audit session.log
```

For real-time monitoring, use `--watch` (`-w`) to tail the log and print denials as they happen:

```bash
# In one terminal:
scode --log session.log --strict codex
# In another:
scode audit --watch session.log
```

Output groups denied paths by their blocked parent directory. For default/platform blocks, it suggests the minimal set of `--allow` flags. Custom policy blocks (`--block`, config `blocked:`, project config) are labeled "Blocked by custom policy" with no `--allow` suggestion — the user blocked them intentionally. Logs can include both `# blocked:` and `# allowed:` metadata; `audit` uses both when present and falls back to built-in defaults for older logs without metadata. Recognized denial formats:

- macOS `sandbox-exec`: `deny(file-read-data) /path`
- Generic Unix: `/path: Permission denied`, `/path: Operation not permitted`
- Node.js EACCES: `permission denied, open '/path'`
- Python OSError: `Permission denied: '/path'`

## Browser support

Since scode is itself a sandbox, inner browser sandboxes fail (double-sandboxing). scode automatically prevents this by exporting:

| Variable | Covers |
|----------|--------|
| `SCODE_SANDBOXED=1` | General "inside scode" signal |
| `ELECTRON_DISABLE_SANDBOX=1` | Electron apps (VS Code, Cursor, etc.) |
| `PLAYWRIGHT_MCP_NO_SANDBOX=1` | Playwright MCP server |
| `CHROMIUM_FLAGS="--no-sandbox"` | Chrome/Chromium (Linux distro wrappers) |

For Puppeteer and Playwright library usage, scode injects a Node.js preload module (via `NODE_OPTIONS`) that patches `child_process.spawn`, `spawnSync`, `exec`, `execSync`, `execFile`, and `execFileSync` to add `--no-sandbox` when launching Chromium binaries. No code changes needed.

For Claude Code with Playwright, create `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--no-sandbox"]
    }
  }
}
```

## Platform notes

**macOS** — uses `sandbox-exec` (built-in). Allow-default profile with deny rules. `~/Library` is blocked with read-only and read-write carve-outs for essential subdirs. `sandbox-exec` is deprecated by Apple but still functional as of macOS 26. Tested on current macOS releases.

**Linux** — uses `bubblewrap` (install separately). Home dir is bound; blocked dirs are overlaid with tmpfs. Tested on Debian/Ubuntu; other distros may work but are not guaranteed.

**Both platforms:**
- **Strict mode** — deny-default, allow essentials (`/usr`, `/opt`, system dirs). Auto-allows harness config dir when a known harness is detected. On macOS, strict mode also adds `~/Library` carve-outs for known harnesses.
- **`--block` under project dir** — if the project dir sits under a blocked parent, the project-dir override re-allows the entire project subtree. `--block` on subdirectories within the project will not take effect in this case.

## Tips

### Shell aliases

If you use the same flags often, aliases save typing. Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Per-harness shortcuts
alias sclaude='scode claude'
alias scodex='scode codex'
alias sopencode='scode opencode'

# Or shadow the harness directly — never run unsandboxed by accident
alias claude='scode claude'
alias codex='scode codex'

# Flag presets
alias scode-strict='scode --strict'
alias scode-ro='scode --ro'
alias scode-paranoid='scode --config ~/.config/scode/sandbox-paranoid.yaml'
alias scode-nonet='scode --no-net'
```

Or skip aliases entirely and bake flags into your config file:

```yaml
# ~/.config/scode/sandbox.yaml
strict: true
scrub_env: true
```

Then `scode claude` picks up those defaults automatically.

### Multiple config files

Keep different configs for different situations:

```
~/.config/scode/
  sandbox.yaml              # daily driver (default)
  sandbox-paranoid.yaml     # untrusted code review
  sandbox-cloud-eng.yaml    # infra work
```

Switch between them with `--config`:

```bash
scode --config ~/.config/scode/sandbox-paranoid.yaml gemini
```

## FAQ

**Some harnesses already have sandboxes. Why use scode?**

A few do. Claude Code has a permission system and an opt-in OS-level sandbox (Seatbelt on macOS, bubblewrap on Linux). Codex CLI uses OS-level sandboxing (Seatbelt/Landlock+seccomp), enabled by default. Gemini CLI and Qwen Code have opt-in OS-level sandboxes, disabled by default. Most others (OpenCode, Goose, Droid, etc.) have no meaningful OS-level isolation.

Even for the ones that do, each harness implements its own policy with its own defaults, its own gaps, and its own config format. scode gives you a single boundary across all of them — one config file, one set of rules, audited once. Switch harnesses without relearning sandbox config. Run multiple harnesses on the same project with identical protections.

**Is it safe to use `--dangerously-skip-permissions` or YOLO mode with scode?**

Safer, yes. Those modes let the harness run tools without asking you first — which is great for speed but risky if the harness wanders. With scode, the OS-level sandbox caps what damage is possible: the harness can freely modify files inside your project, but it still cannot read `~/.aws`, `~/Documents`, `~/.1password`, or any other blocked path. You can accept permissions more freely and worry less about fat-finger approvals. scode does not make YOLO mode "safe" in an absolute sense, but it makes the worst case a lot less bad. Note that `~/.ssh` is not blocked by default (git needs it) — add `--block ~/.ssh` if you want that protection too.

**When is scode NOT useful?**

If you only use one harness, only for a single scoped project, and never give it tasks that touch anything outside that project directory — scode adds little value. The harness can only see what you point it at anyway.

It starts to matter when you use multiple harnesses, when your projects sit next to sensitive files, or when you give harnesses broader tasks — cross-project work, system admin, file management — where a mistake can do real damage. It is also just nice to have a safety net that does not depend on each harness getting its own isolation right.

**Does scode slow anything down?**

Barely. `sandbox-exec` and `bubblewrap` add negligible overhead — your process runs at native speed. The only cost is ~10ms for scode to generate the profile and launch.

**Can I use scode with tools that are not AI harnesses?**

Yes. `scode -- npm test`, `scode -- make build`, or any other command works. You will get a warning that it is not a known harness (meaning sandbox behavior has not been specifically tested for it), but it will still run sandboxed.

**Why is `~/.ssh` not blocked by default?**

SSH keys are needed for git operations over SSH, which is common during development. Blocking them by default would break `git clone`, `git push`, etc. inside the sandbox. If you want to block SSH keys, use `--block ~/.ssh` or add it to your config file.

**Why not just use Docker?**

Docker solves a different problem. Full environment isolation, but you pay for it: a running daemon, image management, volume mounts, networking config. You lose access to host tools, keychains, SSH agents, GUI apps — all stuff that AI harnesses actually need. You can make it work, but it is tedious and the result does not feel native.

scode does the opposite. Your harness runs normally, with full access to your tools and environment. scode just blocks the specific directories it has no business touching. One script, ~10ms startup, nothing changes about how your tools work.

**Apple deprecated `sandbox-exec`. Will scode break?**

Apple has marked `sandbox-exec` as deprecated since macOS 10.x, but it still works fine as of macOS 26 (Tahoe). Apple's own App Sandbox and system services use the same kernel framework underneath (`libsandbox` / Seatbelt). "Deprecated" here means Apple is not committing to the API long-term — not that they are removing it. If they do eventually pull it, scode will need to move to something else (probably Endpoint Security framework). PRs toward that are welcome.

**Does scode support Windows?**

Not yet. scode uses `sandbox-exec` on macOS and `bubblewrap` on Linux — there is no equivalent lightweight mechanism on Windows. PRs adding Windows support (Windows Sandbox, AppContainers, or similar) are welcome.

**Which Linux distros are tested?**

`scode` is tested on macOS and on Linux with Debian/Ubuntu. Other Linux distributions may work, but are not currently guaranteed/supported by test coverage.

**Is scode secure against sandbox escapes?**

No. scode is a best-effort defense, not a hard security boundary. The underlying mechanisms (`sandbox-exec`, `bubblewrap`) are solid, but scode does not claim to stop deliberate escape attempts or kernel-level exploits. It is meant to catch the common case: an AI harness that wanders into your personal documents or 1Password vault by mistake. Not a determined attacker. Seatbelt, not armored vehicle.

**Are there other tools like this?**

Yes. The space is active:

- **Built-in sandboxes** — Claude Code, Codex CLI, and Gemini CLI each ship their own. These are harness-specific: different config formats, different defaults, and you cannot carry policy across tools.
- **Anthropic Sandbox Runtime (`srt`)** — uses sandbox-exec + bubblewrap like scode, and adds proxy-based network filtering. Heavier (requires a proxy daemon), but has finer-grained network control.
- **Agent-specific wrappers** (`cco`, `claude-sandbox`, etc.) — target a single harness. Good if you only use that one tool.
- **Capability sandboxes** (`nono`) — kernel-enforced (Landlock/Seatbelt) with secure key injection. Different model: capability-based rather than policy-based.
- **Container approaches** (Docker Sandboxes, Devcontainers) — full isolation, but you lose host tools, keychains, SSH agents, and native performance. Good for CI, heavy for daily use.

scode is positioned as the **agent-agnostic, zero-dependency, config-driven** option. One bash script, one YAML policy, works with any command. If you already have something that works for you, keep using it.

**I found a bug / I want a feature / the defaults are wrong for my setup.**

Open an issue or PR on [GitHub](https://github.com/bindsch/scode). This is beta software, the defaults are opinionated, and it has not been tested on every setup. Bug fixes, better sandbox coverage, new harness support, default adjustments — all welcome.

## Running tests

```bash
brew install bats-core shellcheck   # or: apt install bats shellcheck
make test                           # runs shellcheck + bats
```

`make test` runs `shellcheck scode` followed by the full `bats` test suite. You can also run them separately:

```bash
make lint    # shellcheck only
bats test/   # bats only
```

## Release checklist

Use [`docs/RELEASE-GATE.md`](docs/RELEASE-GATE.md) before tagging a release.

## License

[MIT](LICENSE)

## Author

Laurent Bindschaedler ([@bindsch](https://github.com/bindsch))
