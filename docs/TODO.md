

## Antigravity login inside the sandbox

Antigravity keeps its login in the macOS Keychain (one generic-password item written through go-keyring,
which shells out to `/usr/bin/security`), and reads no file store. Blocking `~/Library` therefore hides
the login from a sandboxed `agy`. A read-only carve-out of `~/Library/Keychains` was tried on 2026-10-12
and rejected in review: because the items' access lists trust `/usr/bin/security`, any sandboxed child
could dump every Keychain item (Claude Code's, gh's, Antigravity's refresh token included). codemux now
builds a per-run mirror keychain holding only the Antigravity item inside the run's private HOME, which
`security` resolves through HOME, so scode needs no carve-out. If scode ever offers an Antigravity option
itself, it must be that mirror, never a Keychains carve-out.

