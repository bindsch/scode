#!/usr/bin/env bats
# no-sandbox.js Node.js preload module

load test_helper

# ---------- Preload patches child_process ----------

@test "preload injects command flag in execSync shell chains" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('\"' + bin + '\" --headless && echo done', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"done"* ]]
}

@test "preload injects command flag with sudo -u wrapper" {
  require_node
  local tool_dir="$TEST_PROJECT/tools"
  local val
  mkdir -p "$tool_dir"

  cat > "$tool_dir/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user|-g|--group|-h|--host|-p|--prompt|-C|--close-from|-R|--chroot|-D|--chdir|-r|--role|-t|--type)
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      shift
      ;;
    *)
      break
      ;;
  esac
done
exec "$@"
EOF
  chmod +x "$tool_dir/sudo"

  val=$(PATH="$tool_dir:$PATH" SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('sudo -u alice \"' + bin + '\" --headless', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)

  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload injects --no-sandbox for spawnSync sudo -u wrapper API" {
  require_node
  local tool_dir="$TEST_PROJECT/tools-sudo-spawn"
  local val
  mkdir -p "$tool_dir"

  cat > "$tool_dir/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user|-g|--group|-h|--host|-p|--prompt|-C|--close-from|-R|--chroot|-D|--chdir|-r|--role|-t|--type)
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      shift
      ;;
    *)
      break
      ;;
  esac
done
exec "$@"
EOF
  chmod +x "$tool_dir/sudo"

  val=$(PATH="$tool_dir:$PATH" SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('sudo', ['-u', 'alice', bin, '--headless'], { encoding: 'utf8' });
    console.log(String(r.stdout || '').trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)

  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload injects --no-sandbox for spawnSync sudo --user= wrapper API" {
  require_node
  local tool_dir="$TEST_PROJECT/tools-sudo-user-eq"
  local val
  mkdir -p "$tool_dir"

  cat > "$tool_dir/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user=*|--group=*|--host=*|--prompt=*|--close-from=*|--chroot=*|--chdir=*|--role=*|--type=*)
      shift
      ;;
    -u|--user|-g|--group|-h|--host|-p|--prompt|-C|--close-from|-R|--chroot|-D|--chdir|-r|--role|-t|--type)
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      shift
      ;;
    *)
      break
      ;;
  esac
done
exec "$@"
EOF
  chmod +x "$tool_dir/sudo"

  val=$(PATH="$tool_dir:$PATH" SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('sudo', ['--user=alice', bin, '--headless'], { encoding: 'utf8' });
    console.log(String(r.stdout || '').trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)

  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload patches child_process.spawn" {
  require_runtime_sandbox
  require_node
  local val
  val=$("$SCODE" -C "$TEST_PROJECT" -- node -e "
    const cp = require('child_process');
    console.log(cp.spawn.name);
  " 2>/dev/null)
  [[ "$val" == "patchedSpawn" ]]
}

@test "preload injects --no-sandbox for chromium binaries" {
  require_runtime_sandbox
  require_node
  local val
  val=$("$SCODE" -C "$TEST_PROJECT" -- node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync(bin, ['--headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload injects --no-sandbox for chromium spawnSync(options-only overload)" {
  require_runtime_sandbox
  require_node
  local val
  val=$("$SCODE" -C "$TEST_PROJECT" -- node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync(bin, { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload does not inject for non-chromium binaries" {
  require_runtime_sandbox
  require_node
  local val
  val=$("$SCODE" -C "$TEST_PROJECT" -- node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/myapp';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync(bin, ['--flag'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == "--flag" ]]
}

@test "preload injects --no-sandbox for chromium execFileSync API" {
  require_runtime_sandbox
  require_node
  local val
  val=$("$SCODE" -C "$TEST_PROJECT" -- node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.execFileSync(bin, ['--headless'], { encoding: 'utf8' });
    console.log(String(r).trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

# ---------- no-sandbox.js: null args ----------

@test "preload handles null args in spawn" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync(bin, null, { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

# ---------- no-sandbox.js: non-chromium not affected ----------

@test "preload does not inject for binaries with chrome substring" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/my-chromecast-tool';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync(bin, ['--flag'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  # With word boundaries, 'my-chromecast-tool' should NOT match
  [[ "$val" != *"--no-sandbox"* ]]
}

# ---------- no-sandbox.js: double-load guard ----------

@test "preload double-load does not break" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS --require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    console.log(cp.spawn.name);
  " 2>/dev/null)
  [[ "$val" == "patchedSpawn" ]]
}

# ---------- no-sandbox.js: exec async API ----------

@test "preload injects --no-sandbox in exec (async)" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    cp.exec('\"' + bin + '\" --headless', (err, stdout) => {
      console.log(stdout.trim());
      fs.unlinkSync(bin);
    });
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox in execFile (async)" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    cp.execFile(bin, ['--headless'], (err, stdout) => {
      console.log(stdout.trim());
      fs.unlinkSync(bin);
    });
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

# ---------- no-sandbox.js: inactive without SCODE_SANDBOXED ----------

@test "preload does not patch when SCODE_SANDBOXED is not set" {
  require_node
  local val
  val=$(NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    console.log(cp.spawn.name);
  " 2>/dev/null)
  [[ "$val" != "patchedSpawn" ]]
}

# ---------- Shell-wrapped Chromium injection ----------

@test "preload injects --no-sandbox for spawn with {shell:true}" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync(bin, ['--headless'], { shell: true, encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload injects --no-sandbox for shell command string in spawn" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('\"' + bin + '\" --headless', { shell: true, encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for bash -c chromium wrapper" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('bash', ['-c', '\"' + bin + '\" --headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for bash -lc chromium wrapper" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('bash', ['-lc', '\"' + bin + '\" --headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for sh -c chromium wrapper" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('sh', ['-c', '\"' + bin + '\" --headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for spawn('nice', ['chromium', ...])" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    // nice is a known wrapper; chromium is in args
    const r = cp.spawnSync('nice', [bin, '--headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload wrapper spawn does not inject for non-chromium" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/myapp';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('nice', [bin, '--flag'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" != *"--no-sandbox"* ]]
}

@test "preload shell wrapper does not inject for non-chromium" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/myapp';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('bash', ['-c', '\"' + bin + '\" --flag'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" != *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for execFileSync bash -c wrapper" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.execFileSync('bash', ['-c', '\"' + bin + '\" --headless'], { encoding: 'utf8' });
    console.log(String(r).trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

# ---------- Grouped/subshell command strings ----------

@test "preload injects --no-sandbox for ( chromium ) subshell" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('( \"' + bin + '\" --headless )', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload injects --no-sandbox for nested parentheses" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('( ( \"' + bin + '\" --headless ) )', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for shell-mode spawn with subshell" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('( \"' + bin + '\" --headless )', [], { shell: true, encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

# ---------- NODE_OPTIONS with spaces in path ----------

@test "preload works when install path contains spaces" {
  require_node
  # Simulate scode installed under a space-containing path
  local space_dir="$TEST_PROJECT/has space/lib"
  mkdir -p "$space_dir"
  cp "$NO_SANDBOX_JS" "$space_dir/no-sandbox.js"
  local link_path="$TEST_PROJECT/no-sandbox-link-$$.js"
  ln -sf "$space_dir/no-sandbox.js" "$link_path"
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require=$link_path" node -e "
    console.log(require('child_process').spawn.name);
  " 2>/dev/null)
  rm -f "$link_path"
  rm -rf "$TEST_PROJECT/has space"
  [[ "$val" == "patchedSpawn" ]]
}

@test "linux dry-run: space-path preload is bound for bwrap" {
  local install_root="$TEST_PROJECT/has space"
  local install_lib="$install_root/lib"
  local project_dir="$TEST_PROJECT/proj"
  local tmp_with_space="$TEST_PROJECT/tmp dir"
  mkdir -p "$install_lib" "$project_dir" "$tmp_with_space"
  cp "$SCODE" "$install_root/scode"
  cp "$NO_SANDBOX_JS" "$install_lib/no-sandbox.js"
  chmod +x "$install_root/scode"

  TMPDIR="$tmp_with_space" _SCODE_PLATFORM=linux run "$install_root/scode" --dry-run -C "$project_dir" -- true
  [ "$status" -eq 0 ]

  local require_path
  require_path="$(echo "$output" | sed -n 's/^#   NODE_OPTIONS=...--require=//p')"
  [[ -n "$require_path" ]]
  [[ "$require_path" != *" "* ]]
  [[ "$output" == *"--ro-bind ${require_path} ${require_path}"* ]]
  [[ ! -e "$require_path" ]]
}

@test "linux runtime: space-path preload symlink is cleaned up without --log" {
  local install_root="$TEST_PROJECT/has space runtime"
  local install_lib="$install_root/lib"
  local project_dir="$TEST_PROJECT/proj-runtime"
  local fake_bin="$TEST_PROJECT/fake-bin-runtime"
  local before after
  mkdir -p "$install_lib" "$project_dir" "$fake_bin"
  cp "$SCODE" "$install_root/scode"
  cp "$NO_SANDBOX_JS" "$install_lib/no-sandbox.js"
  chmod +x "$install_root/scode"

  cat > "$fake_bin/bwrap" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_bin/bwrap"

  before=$(ls /tmp/scode-no-sandbox-${UID}-*.js 2>/dev/null | wc -l | tr -d ' ')
  PATH="$fake_bin:$PATH" _SCODE_PLATFORM=linux run "$install_root/scode" -C "$project_dir" -- true
  [ "$status" -eq 0 ]
  after=$(ls /tmp/scode-no-sandbox-${UID}-*.js 2>/dev/null | wc -l | tr -d ' ')
  [ "$after" -eq "$before" ]
}

# ---------- exec -> execFile double-injection prevention ----------

@test "preload exec does not double-inject --no-sandbox" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    cp.exec('\"' + bin + '\" --headless', (err, stdout) => {
      const output = stdout.trim();
      const count = (output.match(/--no-sandbox/g) || []).length;
      console.log(count);
      fs.unlinkSync(bin);
    });
  " 2>/dev/null)
  # Should appear exactly once, not twice
  [[ "$val" == "1" ]]
}

@test "preload emits one warning when patching falls back after parse failure" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    let warnings = 0;
    process.emitWarning = (msg) => {
      if (String(msg).includes('[scode no-sandbox] patch fallback')) warnings += 1;
    };
    const badArg = { toString() { throw new Error('boom'); } };
    for (let i = 0; i < 2; i += 1) {
      try {
        cp.spawn('nice', [badArg]);
      } catch (_) {}
    }
    console.log(warnings);
  " 2>/dev/null)
  [[ "$val" == "1" ]]
}

# ---------- P2: relative path resolution ----------

@test "--block with relative path is resolved to absolute" {
  mkdir -p "$TEST_PROJECT/reltest"
  mkdir -p "$TEST_PROJECT/other-cwd"
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  # Run from a different directory; relative paths should still anchor to -C project dir.
  (cd "$TEST_PROJECT/other-cwd" && "$SCODE" --dry-run --block ./reltest -C "$TEST_PROJECT" -- true) > "$TEST_PROJECT/output.txt" 2>&1
  local output
  output="$(cat "$TEST_PROJECT/output.txt")"
  # Should contain the project-anchored absolute path, not caller-cwd path.
  [[ "$output" == *"${real_project}/reltest"* ]]
  [[ "$output" != *"${real_project}/other-cwd/reltest"* ]]
  [[ "$output" != *"./reltest"* ]]
}

@test "--allow with relative path is resolved against project directory" {
  mkdir -p "$TEST_PROJECT/allow-parent/child"
  mkdir -p "$TEST_PROJECT/other-cwd"
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  (cd "$TEST_PROJECT/other-cwd" && "$SCODE" --dry-run --block ./allow-parent --allow ./allow-parent/child -C "$TEST_PROJECT" -- true) > "$TEST_PROJECT/allow-output.txt" 2>&1
  local output
  output="$(cat "$TEST_PROJECT/allow-output.txt")"
  [[ "$output" == *"${real_project}/allow-parent/child"* ]]
  [[ "$output" != *"${real_project}/other-cwd/allow-parent/child"* ]]
  [[ "$output" != *"./allow-parent/child"* ]]
}

# Relative paths in config blocked/allowed are also project-anchored.
@test "config relative blocked path resolves against project directory" {
  local cfg="$TEST_PROJECT/rel-config.yaml"
  mkdir -p "$TEST_PROJECT/cfg-test" "$TEST_PROJECT/other-cwd"
  cat > "$cfg" <<'YAML'
blocked:
  - ./cfg-test
YAML
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  (cd "$TEST_PROJECT/other-cwd" && "$SCODE" --dry-run --config "$cfg" -C "$TEST_PROJECT" -- true) > "$TEST_PROJECT/cfg-output.txt" 2>&1
  local output
  output="$(cat "$TEST_PROJECT/cfg-output.txt")"
  [[ "$output" == *"${real_project}/cfg-test"* ]]
  [[ "$output" != *"${real_project}/other-cwd/cfg-test"* ]]
  [[ "$output" != *"./cfg-test"* ]]
}

@test "config relative allowed path resolves against project directory" {
  local cfg="$TEST_PROJECT/rel-allow-config.yaml"
  mkdir -p "$TEST_PROJECT/cfg-allow-parent/child" "$TEST_PROJECT/other-cwd"
  cat > "$cfg" <<'YAML'
blocked:
  - ./cfg-allow-parent
allowed:
  - ./cfg-allow-parent/child
YAML
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  (cd "$TEST_PROJECT/other-cwd" && "$SCODE" --dry-run --config "$cfg" -C "$TEST_PROJECT" -- true) > "$TEST_PROJECT/cfg-allow-output.txt" 2>&1
  local output
  output="$(cat "$TEST_PROJECT/cfg-allow-output.txt")"
  [[ "$output" == *"${real_project}/cfg-allow-parent/child"* ]]
  [[ "$output" != *"${real_project}/other-cwd/cfg-allow-parent/child"* ]]
  [[ "$output" != *"./cfg-allow-parent/child"* ]]
}

# ---------- Chromium wrapper: nice ----------

@test "preload injects --no-sandbox for nice wrapper" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('nice -n 5 \"' + bin + '\" --headless', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for timeout wrapper" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('timeout 30 \"' + bin + '\" --headless', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for stdbuf wrapper" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('stdbuf -oL \"' + bin + '\" --headless', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for command wrapper" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('command \"' + bin + '\" --headless', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for strace wrapper" {
  require_node
  local tool_dir="$TEST_PROJECT/tools"
  local val
  mkdir -p "$tool_dir"

  cat > "$tool_dir/strace" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|-e|-p|-k|--kill-after|-s|--signal|-n|--adjustment|-i|--input|--output|--error)
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      shift
      ;;
    *)
      break
      ;;
  esac
done
exec "$@"
EOF
  chmod +x "$tool_dir/strace"

  val=$(PATH="$tool_dir:$PATH" SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('strace -f \"' + bin + '\" --headless', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)

  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

# ---------- Chromium pattern: msedge ----------

@test "preload injects --no-sandbox for msedge binary" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/msedge';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync(bin, ['--headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

# ---------- Chromium pattern: headless-shell ----------

@test "preload injects --no-sandbox for headless-shell binary" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/headless-shell';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync(bin, ['--headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

# ---------- Chromium pattern: brave ----------

@test "preload injects --no-sandbox for brave binary" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/brave';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync(bin, ['--headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

# ---------- env -u wrapper ----------

@test "preload injects --no-sandbox for env -u wrapper" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('env -u DISPLAY \"' + bin + '\" --headless', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for taskset wrapper" {
  require_node
  local tool_dir="$TEST_PROJECT/tools"
  local val
  mkdir -p "$tool_dir"

  cat > "$tool_dir/taskset" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -gt 0 && "$1" == -* ]]; then
  shift
fi
if [[ $# -gt 0 ]]; then
  shift
fi
exec "$@"
EOF
  chmod +x "$tool_dir/taskset"

  val=$(PATH="$tool_dir:$PATH" SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('taskset 0x3 \"' + bin + '\" --headless', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)

  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload injects --no-sandbox for ionice -c wrapper" {
  require_node
  local tool_dir="$TEST_PROJECT/tools"
  local val
  mkdir -p "$tool_dir"

  cat > "$tool_dir/ionice" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--class|--classdata|-n|-p)
      shift 2
      ;;
    -t|--ignore)
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      shift
      ;;
    *)
      break
      ;;
  esac
done
exec "$@"
EOF
  chmod +x "$tool_dir/ionice"

  val=$(PATH="$tool_dir:$PATH" SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = String(cp.execSync('ionice -c 2 \"' + bin + '\" --headless', { encoding: 'utf8' })).trim();
    console.log(r);
    fs.unlinkSync(bin);
  " 2>/dev/null)

  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

# ---------- P2 regression: env wrapper preload ----------

@test "preload injects --no-sandbox for spawn('env', ['chromium', ...])" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('env', [bin, '--headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload injects --no-sandbox for spawn('env', ['FOO=bar', 'chromium', ...])" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('env', ['FOO=bar', bin, '--headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload env wrapper does not inject for non-chromium" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/myapp';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('env', ['FOO=bar', bin, '--flag'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" != *"--no-sandbox"* ]]
}

@test "preload injects --no-sandbox for spawn('env', ['-u', 'X', 'chromium'])" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('env', ['-u', 'DISPLAY', bin, '--headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
}

# ---------- patchWrapperArgs: nice numeric positional ----------

@test "preload injects --no-sandbox for spawn('nice', ['-n', '5', 'chromium', ...])" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('nice', ['-n', '5', bin, '--headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload patchWrapperArgs handles ionice -c class before chromium" {
  require_node
  command -v ionice >/dev/null 2>&1 || skip "ionice not available"
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('ionice', ['-c', '2', bin, '--headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}

@test "preload injects --no-sandbox for spawn('timeout', ['30', 'chromium', ...])" {
  require_node
  local val
  val=$(SCODE_SANDBOXED=1 NODE_OPTIONS="--require $NO_SANDBOX_JS" node -e "
    const cp = require('child_process');
    const fs = require('fs');
    const bin = '$TEST_PROJECT/chromium';
    fs.writeFileSync(bin, '#!/bin/bash\necho \"\\\$@\"', { mode: 0o755 });
    const r = cp.spawnSync('timeout', ['30', bin, '--headless'], { encoding: 'utf8' });
    console.log(r.stdout.trim());
    fs.unlinkSync(bin);
  " 2>/dev/null)
  [[ "$val" == *"--no-sandbox"* ]]
  [[ "$val" == *"--headless"* ]]
}
