#!/usr/bin/env bats
# Package entry scripts must select the harness's state grants.

load test_helper

@test "detect_harness returns copilot for its package entry script" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /x/node_modules/@github/copilot/npm-loader.js
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+copilot:"* ]]
  [[ "$output" != *"not a known harness"* ]]
}

@test "detect_harness returns copilot for its bare relative package entry script" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- node_modules/@github/copilot/npm-loader.js
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+copilot:"* ]]
  [[ "$output" != *"not a known harness"* ]]
}

@test "detect_harness returns pi for its package bundle" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /x/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+pi:"* ]]
  [[ "$output" == *"$HOME/.pi/agent"* ]]
  [[ "$output" != *"not a known harness"* ]]
}

@test "detect_harness leaves a harness package's nested dependency unknown" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /x/node_modules/@earendil-works/pi-coding-agent/node_modules/semver/bin/semver.js
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a known harness"* ]]
  [[ "$output" != *"strict+"* ]]
  [[ "$output" != *"auto-allowing"* ]]
  [[ "$output" != *"$HOME/.pi/agent"* ]]
}

@test "detect_harness leaves an unrelated cli.js unknown" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /x/node_modules/other/cli.js
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a known harness"* ]]
  [[ "$output" != *"strict+"* ]]
  [[ "$output" != *"auto-allowing"* ]]
}

@test "copilot package entry policy grants ~/.copilot read-write access" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /x/node_modules/@github/copilot/npm-loader.js
  [ "$status" -eq 0 ]
  local grants
  grants="$(printf '%s\n' "$output" | sed -n '/Harness auto-allowed state directories (read-write)/,/^$/p')"
  [[ "$grants" == *"(allow file-read* file-write*"* ]]
  [[ "$grants" == *"(subpath \"$HOME/.copilot\")"* ]]
}

@test "detect_harness returns claude for its package entry script" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /x/node_modules/@anthropic-ai/claude-code/cli.js
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude:"* ]]
}

@test "detect_harness returns codex for its package entry script" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /x/node_modules/@openai/codex/bin/codex.js
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+codex:"* ]]
}

@test "detect_harness preserves recognition of .exe launchers" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /x/bin/claude.exe
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude:"* ]]
  [[ "$output" != *"not a known harness"* ]]
}

@test "detect_harness checks the basename before the package directory" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /x/node_modules/@github/copilot/bin/codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+codex:"* ]]
  [[ "$output" != *"strict+copilot"* ]]
}

@test "detect_harness requires the complete package directory name" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /x/node_modules/@github/copilot-other/npm-loader.js
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a known harness"* ]]
  [[ "$output" != *"auto-allowing"* ]]
}

@test "detect_harness maps package entry scripts inside transparent wrappers" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- env FOO=bar /x/node_modules/@github/copilot/npm-loader.js
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+copilot:"* ]]
}

@test "detect_harness maps bare relative package entry scripts inside env wrappers" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- env FOO=bar node_modules/@github/copilot/npm-loader.js
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+copilot:"* ]]
  [[ "$output" != *"not a known harness"* ]]
}

@test "detect_harness ignores package entry scripts in command arguments" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- echo /x/node_modules/@github/copilot/npm-loader.js
  [ "$status" -eq 0 ]
  [[ "$output" != *"strict+copilot"* ]]
  [[ "$output" != *"auto-allowing"* ]]
}
