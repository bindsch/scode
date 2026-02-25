// Property-based and regression tests for the no-sandbox.js shell tokenizer
// and injection logic. Uses node:test (Node 18+) and fast-check.

'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fc = require('fast-check');

const {
  tokenizeCommand,
  stripOuterQuotes,
  stripEscapedOuterQuotes,
  isChromiumBinary,
  isShellBinary,
  isEnvBinary,
  isWrapperBinary,
  findCommandToken,
  injectNoSandboxCommand,
} = require('../lib/no-sandbox');

// ===== Arbitrary helpers =====

// Simple word: alphanumeric, dashes, dots, underscores, slashes (no shell metacharacters)
const simpleWord = fc.stringOf(
  fc.constantFrom(...'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./'.split('')),
  { minLength: 1, maxLength: 30 }
);

// A word that is NOT a shell operator or empty
const nonOperatorWord = simpleWord.filter(w => !['|', '||', '&&', ';', '&', '(', ')'].includes(w));

// ===== tokenizeCommand =====

describe('tokenizeCommand', () => {
  it('returns empty array for non-string input', () => {
    assert.deepStrictEqual(tokenizeCommand(undefined), []);
    assert.deepStrictEqual(tokenizeCommand(null), []);
    assert.deepStrictEqual(tokenizeCommand(42), []);
  });

  it('returns empty array for empty string', () => {
    assert.deepStrictEqual(tokenizeCommand(''), []);
  });

  it('property: simple word produces exactly one token', () => {
    fc.assert(fc.property(nonOperatorWord, (word) => {
      const tokens = tokenizeCommand(word);
      assert.strictEqual(tokens.length, 1, `expected 1 token for "${word}", got ${tokens.length}`);
      assert.strictEqual(tokens[0].raw, word);
    }));
  });

  it('property: token indices are monotonically increasing', () => {
    const shellCommand = fc.array(nonOperatorWord, { minLength: 1, maxLength: 10 })
      .map(words => words.join(' '));
    fc.assert(fc.property(shellCommand, (cmd) => {
      const tokens = tokenizeCommand(cmd);
      for (let i = 1; i < tokens.length; i++) {
        assert.ok(tokens[i].index > tokens[i - 1].index,
          `index ${tokens[i].index} not > ${tokens[i - 1].index} in "${cmd}"`);
      }
    }));
  });

  it('property: token raw values with gaps reconstruct the original string', () => {
    const shellCommand = fc.array(nonOperatorWord, { minLength: 1, maxLength: 8 })
      .map(words => words.join(' '));
    fc.assert(fc.property(shellCommand, (cmd) => {
      const tokens = tokenizeCommand(cmd);
      if (tokens.length === 0) return;
      let reconstructed = '';
      let pos = 0;
      for (const tok of tokens) {
        reconstructed += cmd.slice(pos, tok.index) + tok.raw;
        pos = tok.index + tok.raw.length;
      }
      reconstructed += cmd.slice(pos);
      assert.strictEqual(reconstructed, cmd);
    }));
  });

  it('double-quoted strings become single tokens', () => {
    const tokens = tokenizeCommand('echo "hello world" done');
    assert.strictEqual(tokens.length, 3);
    assert.strictEqual(tokens[1].raw, '"hello world"');
  });

  it('single-quoted strings become single tokens', () => {
    const tokens = tokenizeCommand("echo 'hello world' done");
    assert.strictEqual(tokens.length, 3);
    assert.strictEqual(tokens[1].raw, "'hello world'");
  });

  it('assignments with spaces in quotes become single tokens', () => {
    const tokens = tokenizeCommand('FOO="bar baz" chromium');
    assert.strictEqual(tokens.length, 2);
    assert.strictEqual(tokens[0].raw, 'FOO="bar baz"');
  });

  it('assignments with single-quoted values become single tokens', () => {
    const tokens = tokenizeCommand("FOO='bar baz' chromium");
    assert.strictEqual(tokens.length, 2);
    assert.strictEqual(tokens[0].raw, "FOO='bar baz'");
  });

  it('shell operators become their own tokens', () => {
    const tokens = tokenizeCommand('a || b && c ; d | e');
    const ops = tokens.map(t => t.raw);
    assert.deepStrictEqual(ops, ['a', '||', 'b', '&&', 'c', ';', 'd', '|', 'e']);
  });

  it('parentheses are separate tokens', () => {
    const tokens = tokenizeCommand('(echo hi)');
    assert.strictEqual(tokens[0].raw, '(');
    assert.strictEqual(tokens[tokens.length - 1].raw, ')');
  });
});

// ===== stripOuterQuotes =====

describe('stripOuterQuotes', () => {
  it('removes double quotes', () => {
    assert.strictEqual(stripOuterQuotes('"hello"'), 'hello');
  });

  it('removes single quotes', () => {
    assert.strictEqual(stripOuterQuotes("'hello'"), 'hello');
  });

  it('returns non-string input unchanged', () => {
    assert.strictEqual(stripOuterQuotes(42), 42);
    assert.strictEqual(stripOuterQuotes(null), null);
  });

  it('returns short strings unchanged', () => {
    assert.strictEqual(stripOuterQuotes('a'), 'a');
    assert.strictEqual(stripOuterQuotes(''), '');
  });

  it('does not strip mismatched quotes', () => {
    assert.strictEqual(stripOuterQuotes('"hello\''), '"hello\'');
  });
});

// ===== stripEscapedOuterQuotes =====

describe('stripEscapedOuterQuotes', () => {
  it('strips escaped double quotes', () => {
    assert.strictEqual(stripEscapedOuterQuotes('\\"hello\\"'), 'hello');
  });

  it('strips escaped single quotes', () => {
    assert.strictEqual(stripEscapedOuterQuotes("\\'hello\\'"), 'hello');
  });

  it('returns short strings unchanged', () => {
    assert.strictEqual(stripEscapedOuterQuotes('abc'), 'abc');
  });
});

// ===== isChromiumBinary =====

describe('isChromiumBinary', () => {
  it('detects chrome', () => assert.ok(isChromiumBinary('chrome')));
  it('detects chromium', () => assert.ok(isChromiumBinary('chromium')));
  it('detects google-chrome', () => assert.ok(isChromiumBinary('google-chrome')));
  it('detects brave', () => assert.ok(isChromiumBinary('brave')));
  it('detects msedge', () => assert.ok(isChromiumBinary('msedge')));
  it('detects electron', () => assert.ok(isChromiumBinary('electron')));
  it('rejects electron-builder', () => assert.ok(!isChromiumBinary('electron-builder')));
  it('rejects electron-forge', () => assert.ok(!isChromiumBinary('electron-forge')));
  it('rejects electron-packager', () => assert.ok(!isChromiumBinary('electron-packager')));
  it('detects headless-shell', () => assert.ok(isChromiumBinary('headless-shell')));
  it('detects headless_shell', () => assert.ok(isChromiumBinary('headless_shell')));
  it('detects full path /usr/bin/chromium', () => assert.ok(isChromiumBinary('/usr/bin/chromium')));
  it('rejects node', () => assert.ok(!isChromiumBinary('node')));
  it('rejects python', () => assert.ok(!isChromiumBinary('python')));
  it('handles non-string', () => assert.ok(!isChromiumBinary(42)));
  it('handles Buffer', () => assert.ok(isChromiumBinary(Buffer.from('chrome'))));
});

// ===== isShellBinary / isEnvBinary / isWrapperBinary =====

describe('binary detection', () => {
  it('isShellBinary: bash', () => assert.ok(isShellBinary('bash')));
  it('isShellBinary: /bin/sh', () => assert.ok(isShellBinary('/bin/sh')));
  it('isShellBinary: rejects node', () => assert.ok(!isShellBinary('node')));
  it('isEnvBinary: env', () => assert.ok(isEnvBinary('env')));
  it('isEnvBinary: /usr/bin/env', () => assert.ok(isEnvBinary('/usr/bin/env')));
  it('isEnvBinary: rejects bash', () => assert.ok(!isEnvBinary('bash')));
  it('isWrapperBinary: nice', () => assert.ok(isWrapperBinary('nice')));
  it('isWrapperBinary: sudo', () => assert.ok(isWrapperBinary('sudo')));
  it('isWrapperBinary: rejects chromium', () => assert.ok(!isWrapperBinary('chromium')));
});

// ===== findCommandToken =====

describe('findCommandToken', () => {
  it('finds simple command', () => {
    const tok = findCommandToken('ls -la');
    assert.strictEqual(stripOuterQuotes(tok.raw), 'ls');
  });

  it('skips assignments', () => {
    const tok = findCommandToken('FOO=bar baz');
    assert.strictEqual(stripOuterQuotes(tok.raw), 'baz');
  });

  it('skips quoted assignments with spaces', () => {
    const tok = findCommandToken('FOO="bar baz" chromium');
    assert.strictEqual(stripOuterQuotes(tok.raw), 'chromium');
  });

  it('finds command after pipe', () => {
    const tok = findCommandToken('echo hi | grep hi');
    assert.strictEqual(stripOuterQuotes(tok.raw), 'echo');
  });

  it('skips env with flags', () => {
    const tok = findCommandToken('env FOO=bar chromium');
    assert.strictEqual(stripOuterQuotes(tok.raw), 'chromium');
  });

  it('skips nice with numeric priority', () => {
    const tok = findCommandToken('nice -n 5 chromium');
    assert.strictEqual(stripOuterQuotes(tok.raw), 'chromium');
  });

  it('returns null for empty command', () => {
    assert.strictEqual(findCommandToken(''), null);
  });

  it('seekChromium mode finds chromium after non-chromium command', () => {
    const tok = findCommandToken('echo hi; chromium --headless', { seekChromium: true });
    assert.strictEqual(stripOuterQuotes(tok.raw), 'chromium');
  });
});

// ===== injectNoSandboxCommand =====

describe('injectNoSandboxCommand', () => {
  // Generator: a chromium binary name (bare or with path)
  const chromiumBin = fc.constantFrom(
    'chromium', 'chrome', 'google-chrome', 'brave', 'electron',
    'msedge', 'headless-shell', '/usr/bin/chromium', '/usr/bin/chrome'
  );

  // Generator: random flags (--something or -x)
  const flag = fc.oneof(
    simpleWord.map(w => `--${w}`),
    fc.constantFrom('-a', '-v', '-x', '--headless', '--screenshot', '--flag')
  );

  // Generator: chromium command with random flags
  const chromiumCmd = fc.tuple(chromiumBin, fc.array(flag, { minLength: 0, maxLength: 4 }))
    .map(([bin, flags]) => [bin, ...flags].join(' '));

  // Generator: chromium command with optional wrapper prefix
  const wrappedChromiumCmd = fc.oneof(
    chromiumCmd,
    chromiumCmd.map(cmd => `env ${cmd}`),
    chromiumCmd.map(cmd => `nice -n 5 ${cmd}`),
    chromiumCmd.map(cmd => `FOO=bar ${cmd}`),
    chromiumCmd.map(cmd => `sudo ${cmd}`),
    chromiumCmd.map(cmd => `timeout 30 ${cmd}`)
  );

  // Generator: non-chromium binary (no chromium substring)
  const nonChromiumBin = fc.constantFrom(
    'node', 'python', 'ls', 'echo', 'gcc', 'cat', 'grep', 'make', 'git', 'tar'
  );
  const nonChromiumCmd = fc.tuple(nonChromiumBin, fc.array(flag, { minLength: 0, maxLength: 4 }))
    .map(([bin, flags]) => [bin, ...flags].join(' '));

  it('property: idempotent — injecting twice === injecting once', () => {
    fc.assert(fc.property(wrappedChromiumCmd, (cmd) => {
      const once = injectNoSandboxCommand(cmd);
      const twice = injectNoSandboxCommand(once);
      assert.strictEqual(once, twice, `not idempotent for "${cmd}"`);
    }), { numRuns: 200 });
  });

  it('property: non-chromium commands unchanged', () => {
    fc.assert(fc.property(nonChromiumCmd, (cmd) => {
      assert.strictEqual(injectNoSandboxCommand(cmd), cmd);
    }), { numRuns: 200 });
  });

  it('property: output contains --no-sandbox when chromium binary present', () => {
    fc.assert(fc.property(wrappedChromiumCmd, (cmd) => {
      const result = injectNoSandboxCommand(cmd);
      assert.ok(result.includes('--no-sandbox'),
        `expected --no-sandbox in "${result}" for input "${cmd}"`);
    }), { numRuns: 200 });
  });

  it('property: preserves shell operators in multi-segment commands', () => {
    const op = fc.constantFrom('||', '&&', ';', '|');
    const segmented = fc.tuple(chromiumCmd, op, nonChromiumCmd)
      .map(([left, o, right]) => `${left} ${o} ${right}`);
    fc.assert(fc.property(segmented, (cmd) => {
      const result = injectNoSandboxCommand(cmd);
      const tokens = tokenizeCommand(cmd);
      const resultTokens = tokenizeCommand(result);
      // Every operator in the original should appear in the result
      const origOps = tokens.filter(t => ['||', '&&', ';', '|'].includes(t.raw)).map(t => t.raw);
      const resOps = resultTokens.filter(t => ['||', '&&', ';', '|'].includes(t.raw)).map(t => t.raw);
      assert.deepStrictEqual(resOps, origOps,
        `operators changed: ${JSON.stringify(origOps)} → ${JSON.stringify(resOps)}`);
    }), { numRuns: 200 });
  });

  // ===== Regression targets =====

  it('regression: bash -ce "chromium --headless"', () => {
    const result = injectNoSandboxCommand('bash -ce "chromium --headless"');
    assert.ok(result.includes('--no-sandbox'));
    assert.ok(result.includes('chromium'));
    // --no-sandbox must be inside the quoted argument, not appended outside
    assert.ok(result.includes('chromium') && result.includes('--no-sandbox'));
    assert.ok(/bash\s+-ce\s+".*--no-sandbox.*"/.test(result),
      `--no-sandbox should be inside quoted string: "${result}"`);
  });

  it('regression: mixed shell-wrapped and bare chromium segments are both patched', () => {
    const result = injectNoSandboxCommand('bash -c "chromium" && brave');
    const count = (result.match(/--no-sandbox/g) || []).length;
    assert.strictEqual(count, 2, `expected 2 injections in "${result}"`);
    assert.ok(result.includes('bash -c "chromium --no-sandbox"'),
      `expected bash -c segment patched in "${result}"`);
    assert.ok(result.includes('&& brave --no-sandbox'),
      `expected bare brave segment patched in "${result}"`);
  });

  it('regression: chromium after then/do/done/fi/else shell keywords is patched', () => {
    const cmd = 'if true; then chromium --headless; else for i in 1; do brave --headless; done; fi';
    const result = injectNoSandboxCommand(cmd);
    const count = (result.match(/--no-sandbox/g) || []).length;
    assert.strictEqual(count, 2, `expected 2 injections in "${result}"`);
    assert.ok(result.includes('then chromium --no-sandbox --headless'),
      `expected then-branch patched in "${result}"`);
    assert.ok(result.includes('do brave --no-sandbox --headless'),
      `expected do-branch patched in "${result}"`);
  });

  it('regression: chromium in case/esac clause is patched', () => {
    const result = injectNoSandboxCommand('case x in x) chromium --headless ;; esac');
    assert.ok(result.includes('chromium --no-sandbox --headless'),
      `expected case clause patched in "${result}"`);
  });

  it('regression: FOO="bar baz" chromium', () => {
    const result = injectNoSandboxCommand('FOO="bar baz" chromium');
    assert.ok(result.includes('--no-sandbox'));
    // Assignment must precede chromium (not reordered)
    const assignIdx = result.indexOf('FOO="bar baz"');
    const chromIdx = result.indexOf('chromium');
    assert.ok(assignIdx < chromIdx,
      `assignment should precede chromium: "${result}"`);
  });

  it('regression: env chromium --no-sandbox — already has flag, no double inject', () => {
    const cmd = 'env chromium --no-sandbox';
    const result = injectNoSandboxCommand(cmd);
    // Should not add a second --no-sandbox
    const count = (result.match(/--no-sandbox/g) || []).length;
    assert.strictEqual(count, 1, `expected 1 --no-sandbox in "${result}"`);
  });

  it('regression: nice -n 5 chromium — wrapper binary detection', () => {
    const result = injectNoSandboxCommand('nice -n 5 chromium');
    assert.ok(result.includes('--no-sandbox'));
    assert.ok(result.includes('nice -n 5'));
  });

  it('regression: multiple chromium in pipe segments', () => {
    const result = injectNoSandboxCommand('chromium --headless | chromium --screenshot');
    const count = (result.match(/--no-sandbox/g) || []).length;
    assert.strictEqual(count, 2);
  });

  it('regression: chromium already has --no-sandbox in segment', () => {
    const cmd = 'chromium --no-sandbox --headless';
    assert.strictEqual(injectNoSandboxCommand(cmd), cmd);
  });

  it('non-string input returned as-is', () => {
    assert.strictEqual(injectNoSandboxCommand(42), 42);
    assert.strictEqual(injectNoSandboxCommand(null), null);
  });

  it('handles set -e; chromium', () => {
    const result = injectNoSandboxCommand('set -e; chromium');
    assert.ok(result.includes('--no-sandbox'));
  });

  it('handles exec chromium', () => {
    const result = injectNoSandboxCommand('exec chromium');
    assert.ok(result.includes('--no-sandbox'));
  });

  it('handles sudo chromium', () => {
    const result = injectNoSandboxCommand('sudo chromium');
    assert.ok(result.includes('--no-sandbox'));
  });

  it('handles sudo -u user chromium', () => {
    const result = injectNoSandboxCommand('sudo -u user chromium');
    assert.ok(result.includes('--no-sandbox'));
  });

  it('handles timeout 30 chromium', () => {
    const result = injectNoSandboxCommand('timeout 30 chromium');
    assert.ok(result.includes('--no-sandbox'));
  });

  it('regression: timeout --foreground chromium (no duration token)', () => {
    const result = injectNoSandboxCommand('timeout --foreground chromium');
    assert.ok(result.includes('--no-sandbox'),
      `expected injection for "timeout --foreground chromium": "${result}"`);
  });

  it('handles bash -c "chromium --flag"', () => {
    const result = injectNoSandboxCommand('bash -c "chromium --flag"');
    assert.ok(result.includes('--no-sandbox'));
  });

  it('regression: unquoted bash -c chromium keeps injected command as one argument', () => {
    const result = injectNoSandboxCommand('bash -c chromium');
    assert.ok(/bash\s+-c\s+['"]chromium --no-sandbox['"]/.test(result),
      `expected quoted -c command string in "${result}"`);
    assert.ok(!/\bbash\s+-c\s+chromium\s+--no-sandbox\b/.test(result),
      `ineffective split-token form should not be produced: "${result}"`);
  });

  it('handles bash -lc "chromium"', () => {
    const result = injectNoSandboxCommand('bash -lc "chromium"');
    assert.ok(result.includes('--no-sandbox'));
  });

  // --- P1 regression: -p is NOT a flag-with-value for command/time/timeout ---

  it('regression: command -p chromium — -p is boolean', () => {
    const result = injectNoSandboxCommand('command -p chromium');
    assert.ok(result.includes('--no-sandbox'),
      `expected injection for "command -p chromium": "${result}"`);
  });

  it('regression: time -p chromium — -p is boolean', () => {
    const result = injectNoSandboxCommand('time -p chromium');
    assert.ok(result.includes('--no-sandbox'),
      `expected injection for "time -p chromium": "${result}"`);
  });

  it('regression: timeout -p is not a valid flag, chromium still found', () => {
    // timeout does not have -p; it should be treated as a boolean flag
    const result = injectNoSandboxCommand('timeout -p 30 chromium');
    assert.ok(result.includes('--no-sandbox'),
      `expected injection for "timeout -p 30 chromium": "${result}"`);
  });

  // --- shell -c semantics: `--` after -c is the command string itself ---

  it('regression: bash -c -- "chromium --headless" is unchanged', () => {
    const cmd = 'bash -c -- "chromium --headless"';
    assert.strictEqual(injectNoSandboxCommand(cmd), cmd);
  });

  it('regression: sh -c -- "chromium" is unchanged', () => {
    const cmd = 'sh -c -- "chromium"';
    assert.strictEqual(injectNoSandboxCommand(cmd), cmd);
  });

  it('regression: bash -c -- chromium is unchanged', () => {
    const cmd = 'bash -c -- chromium';
    assert.strictEqual(injectNoSandboxCommand(cmd), cmd);
  });

  it('regression: env -S "chromium --headless"', () => {
    const result = injectNoSandboxCommand('env -S "chromium --headless"');
    assert.ok(result.includes('env -S "chromium --no-sandbox --headless"'),
      `expected injection in env -S split string: "${result}"`);
  });
});
