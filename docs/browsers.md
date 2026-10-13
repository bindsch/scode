# Browser compatibility

Nested Chromium sandboxes can fail under scode. The wrapper supplies:

| Variable | Value / purpose |
|---|---|
| `SCODE_SANDBOXED` | `1`, activation marker |
| `ELECTRON_DISABLE_SANDBOX` | `1`, Electron compatibility |
| `PLAYWRIGHT_MCP_NO_SANDBOX` | `1`, Playwright MCP compatibility |
| `CHROMIUM_FLAGS` | Adds `--no-sandbox` for distro wrappers |
| `NODE_OPTIONS` | Loads scode's Node preload when available |

The preload patches `child_process.spawn`, `spawnSync`, `exec`,
`execSync`, `execFile`, and `execFileSync`. It recognizes Chrome,
Chromium, Brave, Edge, headless-shell, and Electron launch names, including
supported platform suffixes. It avoids adding a duplicate flag.

## Supported forms and limits

Direct argument arrays, recognized transparent wrappers, and supported shell
command strings can be rewritten. Shell handling includes assignments,
separators/newlines, brace and negation groups, supported nested wrappers,
shell `-c --`, and supported `env` split-string/chdir forms.
It preserves unrelated `shell: true` behavior.

This is not a complete shell parser. Command substitutions and heredocs are
preserved instead of rewritten. Unrecognized launchers, renamed browser
binaries, dynamic command construction, and launches outside the patched Node
APIs may not receive the flag.

Custom policy that blocks the preload or prevents its safe placement can
disable injection. The exact preload file is granted, not its parent tree.
Check startup warnings and dry-run output. If a browser still reports a nested
sandbox error, pass `--no-sandbox` through the browser's own supported launch
configuration. For example, Playwright MCP accepts it as a server argument:

```json
{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp","--no-sandbox"]}}}
```

Pin a reviewed package version in a real deployment.

## Security tradeoff

Disabling the inner sandbox gives a compromised renderer the authority of the
outer scode policy. That includes readable project data, harness credentials,
and explicit grants. The untrusted preset reduces that authority but can also
prevent network-dependent browser work. Review the [policy](policy.md) before
adding network or filesystem access.
