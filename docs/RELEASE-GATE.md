# Release gate

The canonical checklist is [Release procedure](releases.md).

| Rule | Required evidence |
|---|---|
| scode never reads, copies, changes, or guesses a harness login. It must not invoke a Keychain tool, write a credential file, or initiate a password dialog. | Static launcher checks plus offline fake-harness runs in normal, strict, legacy-flag, and untrusted modes: zero fake security calls, no state writes, existing synthetic mirrors and backups unchanged, no login refusal. |
| Login-store access is opt-in; a harness uses its own store. | macOS profiles deny access by default. CLI/user opt-in grants eligible claude/agy the keychain directory read-write and existing security preferences read-only. Opt-outs, custom blocks, and untrusted suppress the whole grant. Synthetic kernel tests deny preference writes, replacement, and creation when absent. System security remains executable. |
| No sandboxed process can reach the macOS keychain or authorization daemons unless the login-store grant is applied and the login keychain resolves. | One launcher decision yields the file grant and the final Mach deny. Profile-text tests cover default, opt-out, ineligible, untrusted, blocked, strict, read-only, explicit `--allow` of the Keychains directory, and a HOME without a login keychain. A passive kernel test looks up `com.apple.SecurityServer`, `com.apple.securityd.xpc`, `com.apple.authd`, and the security agent names from inside the sandbox (denied) and `com.apple.trustd` (reachable). No test stores to or reads from a keychain. |
| Empty retained environment values stay empty, not unset. | Runtime assertions with and without scrubbing and with explicit keep-env exemptions. |

The first rule governs scode's behavior. It does not prohibit a harness from
using its own Keychain item through `/usr/bin/security` when the login-store
grant is applied; in that case a harness or macOS can still display a dialog.
Without the applied grant, the third rule denies the daemons a dialog needs.
It does not cover a process that a child starts outside the sandbox; see
[keychain services](security.md#keychain-services-on-macos). Do not describe
offline fixture success as live authentication verification.
