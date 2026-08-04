# scode

> **Beta software (v0.3.2).** This is under active development. Defaults may change, features may break, and sandbox coverage is not guaranteed to be complete. Use at your own risk. Pull requests welcome.

scode wraps AI coding tools (Claude, Codex, Aider, Grok, OpenCode, etc.) in an OS-level sandbox that prevents them from reading or modifying personal files, credentials, and sensitive directories. One policy, all agents, zero infrastructure.

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

**Zero infrastructure.** Single bash script. No daemon, no proxy, no container, no language runtime for the core wrapper. Uses the system sandbox on tested macOS versions or `bubblewrap` on tested Debian/Ubuntu releases.

**Batteries included.** Blocks SSH and signing keys, cloud/container/IaC credentials, package tokens, password managers, personal media, and shell histories by default. Chromium double-sandbox issues are handled automatically. Environment scrubbing covers cloud, AI, CI/CD, package, SSH-agent, and process-injection variables.

**YOLO mode safety net.** Running with `--dangerously-skip-permissions` or auto-accepting tool calls? scode still enforces its filesystem and network boundary in the kernel. This limits access to protected host data, but the harness can still damage a writable project or exfiltrate any readable project data while network access is enabled.

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
EXPECTED_COMMIT="8acb5fd9bec18036df6a912518c6c47264b4bdc2" # v0.3.2
git clone --filter=blob:none https://github.com/bindsch/scode.git
cd scode
git checkout --detach "$EXPECTED_COMMIT"
test "$(git rev-parse HEAD)" = "$EXPECTED_COMMIT"
sudo make install
```

Release tags are currently unsigned. Pin and verify the documented commit as
shown; do not install directly from a mutable branch.

Install to a different prefix (no sudo needed):

```bash
make install PREFIX="$HOME/.local"
```

Uninstall:

```bash
sudo make uninstall
```

If you installed with a custom prefix, use the same prefix for uninstall:

```bash
make uninstall PREFIX="$HOME/.local"
```

### Manual

```bash
COMMIT="8acb5fd9bec18036df6a912518c6c47264b4bdc2" # v0.3.2
tmp="$(mktemp -d)"
base="https://raw.githubusercontent.com/bindsch/scode/${COMMIT}"
curl -fsSLo "$tmp/scode" "$base/scode"
curl -fsSLo "$tmp/no-sandbox.js" "$base/lib/no-sandbox.js"
curl -fsSLo "$tmp/LICENSE" "$base/LICENSE"
(cd "$tmp" && printf '%s  %s\n' \
  c6d1380a25190e5e29ea55f04c1fcb433f1e7751f0039b7d11fb68859aecaa67 scode \
  131cb3edc4e5149de8a3ad619824d1b99b8f35b053d0031e6aa46b286a56b944 no-sandbox.js \
  60e0aac1186a0ea1be7c13e1cc7a8475100fae5572abc23bbad33e3cdfa726dd LICENSE \
  | shasum -a 256 -c -)
sudo install -d /usr/local/bin /usr/local/lib/scode /usr/local/share/scode
sudo install -m 755 "$tmp/scode" /usr/local/bin/scode
sudo install -m 644 "$tmp/no-sandbox.js" /usr/local/lib/scode/no-sandbox.js
sudo install -m 644 "$tmp/LICENSE" /usr/local/share/scode/LICENSE
rm -rf "$tmp"
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
scode --strict claude              # deny-default; reads ~/.claude but cannot modify it
scode --trust untrusted codex      # maximum lockdown; no harness-state auto-allow
scode --trust trusted gemini       # minimal sandbox (rw, net on)
scode --scrub-env claude           # strip API keys from env
scode --config examples/sandbox-paranoid.yaml opencode  # use a specific config
scode --log session.log codex      # log denials for review
scode audit session.log            # parse denials, suggest --allow flags
scode audit --watch session.log    # live-tail denials in real-time
scode --config examples/sandbox-grok.yaml grok  # Grok collection defense
```

### Known harnesses

These commands are recognized without needing `--`. In strict mode, scode also
auto-allows their default user config and state paths **read-only**. The
`untrusted` preset disables these automatic openings entirely.

| Harness | Command | Default auto-allowed paths |
|---------|---------|----------------------------|
| OpenCode | `opencode` | `~/.config/opencode`, `~/.local/share/opencode` |
| Claude Code | `claude` | `~/.claude` |
| Codex CLI | `codex` | `~/.codex` |
| Goose | `goose` | `~/.config/goose` |
| Gemini CLI | `gemini` | `~/.gemini` |
| Factory Droid | `droid` | `~/.factory` |
| Qwen Code | `qwen` | `~/.qwen` |
| Codemux | `codemux` | `~/.codemux`, `~/.config/codemux` (legacy) |
| Pi Coding Agent | `pi` | `~/.pi/agent` |
| Aider | `aider` | `~/.aider`, `~/.aider.conf.yml` |
| Amp | `amp` | `~/.config/amp`, `~/.amp` |
| Crush | `crush` | `~/.config/crush`, `~/.local/share/crush` |
| Cursor Agent | `cursor-agent` | `~/.cursor` |
| GitHub Copilot CLI | `copilot` | `~/.copilot`, `~/.cache/copilot` (Linux) |
| Continue CLI | `cn` | `~/.continue` |
| Kimi Code CLI | `kimi` | `~/.kimi-code`, `~/.kimi` (legacy) |
| OpenHands CLI | `openhands` | `~/.openhands` |
| Cline CLI | `cline` | `~/.cline` |
| Kiro CLI | `kiro-cli` | `~/.kiro` |
| Auggie CLI | `auggie` | `~/.augment` |
| Grok CLI | `grok` | `~/.grok` |

If a harness is configured to use a custom user directory, add that path with
`--allow` when using strict mode. Environment-controlled roots such as `GROK_HOME`
are deliberately not auto-allowed because a hostile value such as `/` would
collapse the strict boundary.

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

SSH keys, signing keys, cloud credentials, package tokens, and common histories are already blocked. Add only policy specific to your environment:

```bash
scode --trust untrusted --block ~/Company-Secrets codex
```

Use Linux equivalents where paths differ.

**Harness auto-allow:** When `--strict` detects a known harness as the command binary (or behind transparent wrappers such as `env`, `nice`, `timeout`, `command`, `stdbuf`, `ionice`, `taskset`, or shell `-c` wrappers), it automatically allows read-only access to:

- The harness config and state paths listed above

This means `scode --strict claude` can read `~/.claude` but cannot modify it. It does not reopen browser profiles, Keychains, or broad macOS `~/Library` subtrees. `scode --trust untrusted claude` does not expose `~/.claude` at all unless the caller explicitly uses `--allow`.

Detection is conservative: only the command binary (or the binary behind supported transparent wrappers) triggers auto-allow. Harness names appearing as arguments do not — `scode --strict -- echo claude` does not auto-allow `~/.claude`.

To suppress a specific harness-state auto-allow, use `--block`:

```bash
scode --strict --block ~/.claude claude
```

For unknown commands or additional paths, add `--allow` manually:

```bash
scode --strict --allow /path/to/build-cache -- npm test
```

If an `--allow` path does not exist in strict mode, scode warns and does **not** create it. Create the directory yourself first.

> **Linux strict note:** `XDG_RUNTIME_DIR` (typically `/run/user/$UID`) is intentionally not bound.
> It contains sockets (Wayland, PulseAudio, D-Bus) that expand attack surface. If a tool
> needs it, add `--allow /run/user/$UID` explicitly.

`--no-net` removes IP networking and omits the default runtime-directory bind on
Linux. Nonstandard inherited descriptors are closed before launch, but standard
input/output/error and an explicitly allowed pathname Unix socket remain
authority channels.

## Configuration

Optional config file at `~/.config/scode/sandbox.yaml`. Entries are merged with built-in defaults:

- `blocked:` adds to the default blocked list
- `allowed:` overrides blocks recursively (the path and all descendants), including defaults and your additions
- Scalar options (`net`, `fs_mode`, `strict`, `scrub_env`, `grok_defense`) set defaults

### Project config

A `.scode.yaml` file in the project root (the `--cwd` directory) is treated as untrusted input. It may tighten the policy by adding blocks, disabling network, enabling strict/env-scrub/Grok defense, or making the project read-only. It cannot add authoritative `allowed:` paths or turn protections off.

```yaml
# .scode.yaml — project-specific sandbox config
strict: true
blocked:
  - ~/Dropbox
allowed:
  - ./data    # ignored unless the user or CLI already authorizes it
```

Priority is CLI flags > user config > restrictive project config > environment variables > built-in defaults. Permissive project values are ignored with a warning. A user config can still make an intentional exception.

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
| `grok_defense` | `true`, `false` | Config-only incident defense |

## Grok CLI defense

The July 2026 Grok Build incident showed two separate outbound paths: ordinary model requests could contain file contents, while a collector created and uploaded a Git bundle containing all tracked files and history. The latter happened independently of the model's file reads. The public reproduction also found that the in-product privacy opt-out controlled retention, not whether trace traffic left the machine.

Enable scode's defense with one user-config setting:

```yaml
# ~/.config/scode/sandbox.yaml
grok_defense: true
```

Then run `scode grok`. For a directly detected Grok command, the mode:

- forces strict mode and environment scrubbing;
- kernel-blocks the project's `.git`, `.grok`, and common `.env` files;
- pins Grok telemetry, trace upload, workspace collection/queue, and relay sync off;
- enables Git-ignore respect and disables auto-update, compatibility scanners, memory, subagents, tool search, and web fetch;
- refuses `/` or either effective/account home as the project root.

The environment pins also protect a nested Grok process, but strict mode and project-file blocks require scode to detect `grok` as the command (directly or through a supported wrapper). `XAI_API_KEY` is scrubbed, so use Grok's interactive/OAuth login with this mode.

For a persistent vendor-side veto, add this separately to `~/.grok/requirements.toml` (or centrally to `/etc/grok/requirements.toml`, which has higher precedence):

```toml
[harness]
disable_codebase_upload = true

[features]
telemetry = false

[telemetry]
trace_upload = false

[tools]
respect_gitignore = true

[cli]
auto_update = false
```

`disable_codebase_upload`, telemetry, and trace-upload are defense-in-depth controls observed in current/recent Grok builds, not a substitute for scode's filesystem boundary. Re-run `grok inspect` and a canary network test after upgrades because the original incident was stopped by a server-side flag and no public root-cause advisory has been published.

**Hard limit:** a cloud CLI needs network access to work. Any project file Grok is allowed to read may be sent as inference input. `net: off` blocks normal IP exfiltration and cloud use, but standard streams or explicitly allowed local sockets remain outside that guarantee. See [Security hardening and research](docs/SECURITY-HARDENING.md) for incident evidence, threat model, and sources.

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

Manual install does not include examples; use the pinned repo files directly.

| File | Use case |
|------|----------|
| [`sandbox.yaml`](examples/sandbox.yaml) | Base template with commented-out common additions |
| [`sandbox-strict.yaml`](examples/sandbox-strict.yaml) | Strict mode with extra blocked directories |
| [`sandbox-paranoid.yaml`](examples/sandbox-paranoid.yaml) | Maximum lockdown for untrusted code review |
| [`sandbox-permissive.yaml`](examples/sandbox-permissive.yaml) | Opens up dirs for trusted projects (docs, datasets) |
| [`sandbox-cloud-eng.yaml`](examples/sandbox-cloud-eng.yaml) | Cloud/infra engineers: allows kubectl/Docker/Helm config dirs |
| [`sandbox-grok.yaml`](examples/sandbox-grok.yaml) | Grok CLI collection and Git-history defense |

## Default protections

### Paths blocked on all platforms

| Category | Representative protected paths |
|---|---|
| Personal data | `~/Documents`, `~/Desktop`, `~/Pictures`, `~/Downloads`, `~/Music`, `~/Movies`, `~/Videos` |
| Private keys | `~/.ssh`, `~/.gnupg`, `~/.pki` |
| Cloud/container/IaC | AWS, Azure, GCP, Kubernetes, Docker/containers, OCI, Terraform, Pulumi, Helm, DigitalOcean, Rclone, SOPS age, Vercel, Netlify, Railway, Fly, Hetzner |
| Password stores/keyrings | 1Password, `pass`, Bitwarden CLI/data, Linux keyrings and KWallet |
| Package/VCS credentials | npm, Yarn, Bun, netrc, Git/GitHub/GitLab, PyPI/pip/Poetry, RubyGems, Cargo, Maven, Gradle, NuGet, Composer, Hugging Face |
| Histories | Bash, Zsh, Python, MySQL, PostgreSQL, and SQLite histories |

### What is NOT blocked

- **Your project directory** -- full read-write access (or read-only with `--ro`).
- **Network** -- fully open by default (disable with `-n`).
- **Harness state outside strict mode** -- for example `~/.claude` or `~/.codex`, unless separately blocked.
- All system paths (`/usr`, `/bin`, `/System`, etc.) and temp directories.

If you do not want this allow-first baseline, use strict mode: `scode --strict ...` or `scode --trust untrusted ...`.

### macOS: ~/Library

`~/Library` is blocked wholesale with no automatic browser, cache, preference, or Keychain carve-outs. Browser profiles contain cookies and bearer sessions; read-only access can still be enough to steal them. If a harness needs one subdirectory, authorize that exact subtree instead of the whole Library:

```bash
scode --allow "$HOME/Library/Application Support/SpecificTool" opencode
```

### Linux: additional blocks

On Linux, scode additionally protects browser/email profiles and application sandboxes:

| Category | Directories |
|---|---|
| Browser profiles | `~/.mozilla`, `~/.config/google-chrome`, `~/.config/chromium`, `~/.config/BraveSoftware` |
| Email / messaging | `~/.thunderbird`, `~/.config/Signal` |
| App sandboxes | `~/.var/app` (Flatpak), `~/snap` |

### Always blocked (both modes)

- `/usr/bin/sudo`, `/usr/bin/su`, `/usr/bin/login`, `/usr/bin/doas`, `/usr/bin/pkexec` -- privilege escalation prevention

## `--scrub-env`

When enabled, strips sensitive environment families before the command runs (not on by default):

- cloud and infrastructure credentials (`AWS_*`, `AZURE_*`, Google/OCI/DigitalOcean, Kubernetes, Vault, Pulumi, Terraform/TFC, Cloudflare);
- AI provider keys (OpenAI, Anthropic, xAI, Gemini, OpenRouter, Hugging Face, Cohere, Mistral, and others);
- VCS, CI/CD, deployment, package-registry, Docker, database URL, and SSH-agent credentials;
- process/startup injection controls such as `BASH_ENV`, `ENV`, `ZDOTDIR`, `LD_*`, `DYLD_*`, `NODE_OPTIONS`, Python/Ruby/Perl/Java startup options, and Git config/askpass overrides.

The exact patterns are maintained in `SCRUB_PATTERNS` in the `scode` script. Grok defense turns scrubbing on automatically for a detected Grok command.

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

Output groups denied paths by their blocked parent directory. For default/platform blocks, it suggests the minimal set of `--allow` flags. Custom policy blocks (`--block`, config `blocked:`, project config) are labeled "Blocked by custom policy" with no `--allow` suggestion — the user blocked them intentionally. Logs can include both `# blocked:` and `# allowed:` metadata; `audit` uses both when present and falls back to built-in defaults for older logs without metadata. New logs begin with a machine-readable `#json:` header line, including an exact `argv` array, followed by legacy `# ...` metadata lines for compatibility. Recognized denial formats:

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

Disabling the inner browser sandbox is a security tradeoff: a compromised renderer inherits everything the outer scode policy permits, including readable project files and any explicit allows. For hostile content, prefer `--trust untrusted` and add only the minimum paths needed; keep network disabled unless the task requires it.

For Puppeteer and Playwright library usage, scode injects a Node.js preload module (via `NODE_OPTIONS`) that patches `child_process.spawn`, `spawnSync`, `exec`, `execSync`, `execFile`, and `execFileSync` to add `--no-sandbox` when launching Chromium binaries. No code changes needed.

For Claude Code with Playwright, create `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@0.0.78", "--no-sandbox"]
    }
  }
}
```

## Platform notes

**macOS** — uses the system `/usr/bin/sandbox-exec`. `~/Library` is blocked without automatic credential-bearing carve-outs. `sandbox-exec` is deprecated; scode checks that the system binary exists and the runtime tests probe it before relying on it.

**Linux** — uses `bubblewrap` (install separately). Home dir is bound; blocked dirs are overlaid with tmpfs. Tested on Debian/Ubuntu; other distros may work but are not guaranteed.

**Both platforms:**
- **Strict mode** — deny-default, allow essentials (`/usr`, `/opt`, system dirs). Auto-allows only read-only access to the detected harness's listed config/state paths. `--trust untrusted` disables that auto-allow.
- **`--block` under project dir** — if the project dir sits under a blocked parent, the project-dir override re-allows the project subtree so work can proceed. `--block` entries inside the project are then re-applied, so blocking project subdirectories still works.

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

Several harnesses provide their own permission or OS-sandbox features, and
their defaults change over time. Consult each harness's current documentation.
scode's purpose is a single outer policy that does not depend on one harness's
approval parser or release-specific defaults.

Even for the ones that do, each harness implements its own policy with its own defaults, its own gaps, and its own config format. scode gives you a single boundary across all of them — one config file, one set of rules, audited once. Switch harnesses without relearning sandbox config. Run multiple harnesses on the same project with identical protections.

**Is it safe to use `--dangerously-skip-permissions` or YOLO mode with scode?**

Safer, but not safe in an absolute sense. scode blocks protected host paths including `~/.ssh`, `~/.aws`, `~/Documents`, and password stores. The harness can still modify a read-write project, execute project code, and send readable project data over an enabled network. Prefer `--trust untrusted` for unknown repositories and keep human approval for consequential actions.

**When is scode NOT useful?**

If you already run one harness inside a separately verified, deny-default
container or VM with no host credentials, sockets, or broad mounts, scode adds
little value. A native host process otherwise inherits ambient filesystem,
environment, descriptor, and service authority beyond the path in its prompt.

It starts to matter when you use multiple harnesses, when your projects sit next to sensitive files, or when you give harnesses broader tasks — cross-project work, system admin, file management — where a mistake can do real damage. It is also just nice to have a safety net that does not depend on each harness getting its own isolation right.

**Does scode slow anything down?**

The sandboxed process runs natively. Startup adds profile construction and one
sandbox-engine launch; measure it on your platform if latency matters.

**Can I use scode with tools that are not AI harnesses?**

Yes. `scode -- npm test`, `scode -- make build`, or any other command works. You will get a warning that it is not a known harness (meaning sandbox behavior has not been specifically tested for it), but it will still run sandboxed.

**Why did Git over SSH stop working?**

`~/.ssh`, `SSH_AUTH_SOCK`, and `SSH_AGENT_PID` are removed from ambient access.
Prefer HTTPS with a narrowly scoped, short-lived credential. If SSH agent
forwarding is necessary, opt in to both the socket path and environment value:

```bash
sock="$SSH_AUTH_SOCK"
scode --allow "$sock" -- env SSH_AUTH_SOCK="$sock" git fetch
```

This grants the sandbox signing/authentication authority for that agent.

**Why not just use Docker?**

Docker solves a different problem. Full environment isolation, but you pay for it: a running daemon, image management, volume mounts, networking config. You lose access to host tools, keychains, SSH agents, GUI apps — all stuff that AI harnesses actually need. You can make it work, but it is tedious and the result does not feel native.

scode keeps native host tooling while applying filesystem, environment, and
network policy. That compatibility also means explicitly allowed host services
remain part of the sandbox's authority.

**Apple deprecated `sandbox-exec`. Will scode break?**

`sandbox-exec` is deprecated and Apple does not promise long-term compatibility.
The system binary is still present and scode's runtime probes pass on the tested
macOS 26 host, but a future update can change or remove it. If the probe fails,
scode stops instead of running unsandboxed. A replacement backend would require
a separately designed and tested macOS security architecture.

**Does scode support Windows?**

Not yet. scode uses `sandbox-exec` on macOS and `bubblewrap` on Linux — there is no equivalent lightweight mechanism on Windows. PRs adding Windows support (Windows Sandbox, AppContainers, or similar) are welcome.

**Which Linux distros are tested?**

`scode` is tested on macOS and on Linux with Debian/Ubuntu. Other Linux distributions may work, but are not currently guaranteed/supported by test coverage.

**Is scode secure against sandbox escapes?**

No. scode is a best-effort policy wrapper, not a complete security boundary.
Bubblewrap constructs namespaces and mounts from scode's policy; it does not
define that policy itself. Apple's `sandbox-exec` interface is deprecated and
imports a private system profile for compatibility. Neither protects against
kernel/sandbox-engine vulnerabilities, authority carried by standard streams,
or authority the caller explicitly allows.

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
brew install bats-core shellcheck node kcov   # use Node.js 22+; install equivalents on Linux
npm ci
make test                                 # runs shellcheck + JS tests + bats
make coverage                             # enforces >=80% shell and JS coverage
```

`make test` runs `shellcheck scode`, `make test-js`, then the full `bats` suite. You can also run them separately:

```bash
make lint      # shellcheck only
make test-js   # Node.js preload tests
bats test/     # bats only
```

## Release checklist

Use [`docs/RELEASE-GATE.md`](docs/RELEASE-GATE.md) before tagging a release.

## License

[MIT](LICENSE)

## Author

Laurent Bindschaedler ([@bindsch](https://github.com/bindsch))
