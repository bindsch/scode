// scode no-sandbox preload module
// Loaded via NODE_OPTIONS="--require=/path/to/no-sandbox.js"
// Patches child_process.spawn to inject --no-sandbox when launching Chromium.
// Only activates when SCODE_SANDBOXED=1 is set.
//
// Note: bare `return` statements below are valid because Node's --require
// wraps the file in a function scope (CommonJS module wrapper).

'use strict';

if (process.env.SCODE_SANDBOXED !== '1') {
  return;
}

// Guard against double-loading (e.g. multiple --require entries)
if (global.__scode_no_sandbox_loaded) {
  return;
}
global.__scode_no_sandbox_loaded = true;

const childProcess = require('child_process');

// Patterns that identify a Chromium binary
const CHROMIUM_PATTERNS = [
  /\bchrom(?:e|ium)\b/i,
  /\bbrave\b/i,
  /\bmsedge\b/i,
  /\bmicrosoft-edge\b/i,
  /\belectron\b/i,
  /\bheadless[_-]?shell\b/i,
];

let patchWarningEmitted = false;

function emitPatchWarning(apiName, error) {
  if (patchWarningEmitted) return;
  patchWarningEmitted = true;
  const detail =
    error && typeof error === 'object' && 'message' in error
      ? error.message
      : String(error);
  const message = `[scode no-sandbox] patch fallback in ${apiName}: ${detail}`;
  if (typeof process.emitWarning === 'function') {
    process.emitWarning(message);
    return;
  }
  try {
    console.error(message);
  } catch (_) {}
}

function isChromiumBinary(cmd) {
  if (Buffer.isBuffer(cmd)) {
    cmd = cmd.toString('utf8');
  }
  if (typeof cmd !== 'string') return false;
  cmd = stripEscapedOuterQuotes(stripOuterQuotes(cmd.trim()));
  const basename = cmd.split('/').pop().split('\\').pop();
  return CHROMIUM_PATTERNS.some(p => p.test(basename));
}

function injectNoSandbox(args) {
  if (!Array.isArray(args)) return args;
  if (args.includes('--no-sandbox')) return args;
  return ['--no-sandbox', ...args];
}

function fallbackInjectArgs(command, args) {
  if (!isChromiumBinary(command)) {
    return args;
  }
  try {
    return injectNoSandbox(args);
  } catch (_) {
    return args;
  }
}

function normalizeSpawnOverload(args, options) {
  if (Array.isArray(args)) {
    return { args, options };
  }
  if (typeof args === 'undefined' || args === null) {
    return { args: [], options };
  }
  if (args && typeof args === 'object') {
    return { args: [], options: args };
  }
  return { args, options };
}

function normalizeExecFileOverload(args, options, callback) {
  if (Array.isArray(args)) {
    return { args, options, callback };
  }
  if (typeof args === 'function') {
    return { args: [], options: undefined, callback: args };
  }
  if (typeof args === 'undefined' || args === null) {
    return { args: [], options, callback };
  }
  if (args && typeof args === 'object') {
    return { args: [], options: args, callback: options };
  }
  return { args, options, callback };
}

function normalizeExecFileSyncOverload(args, options) {
  if (Array.isArray(args)) {
    return { args, options };
  }
  if (typeof args === 'undefined' || args === null) {
    return { args: [], options };
  }
  if (args && typeof args === 'object') {
    return { args: [], options: args };
  }
  return { args, options };
}

function normalizeExecOverload(options, callback) {
  if (typeof options === 'function') {
    return { options: undefined, callback: options };
  }
  return { options, callback };
}

function tokenizeCommand(command) {
  if (typeof command !== 'string') return [];
  const tokens = [];
  // Split shell control operators and grouping chars as standalone tokens.
  // Keep quoted strings intact so embedded whitespace/operators are preserved.
  const tokenRegex = /[A-Za-z_][A-Za-z0-9_]*=(?:"([^"\\]|\\.)*"|'[^']*'|[^ \t\r\n\f\v;|&()]*)|"([^"\\]|\\.)*"|'[^']*'|\|\||&&|[;|&()]|[^ \t\r\n\f\v;|&()]+/g;
  let match;
  while ((match = tokenRegex.exec(command)) !== null) {
    tokens.push({ raw: match[0], index: match.index });
  }
  return tokens;
}

function stripOuterQuotes(token) {
  if (typeof token !== 'string' || token.length < 2) return token;
  const first = token[0];
  const last = token[token.length - 1];
  if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
    return token.slice(1, -1);
  }
  return token;
}

function stripEscapedOuterQuotes(token) {
  if (typeof token !== 'string' || token.length < 4) return token;
  const hasEscapedDouble = token.startsWith('\\"') && token.endsWith('\\"');
  const hasEscapedSingle = token.startsWith("\\'") && token.endsWith("\\'");
  if (hasEscapedDouble || hasEscapedSingle) {
    return token.slice(2, -2);
  }
  return token;
}

function isAssignmentToken(token) {
  return /^[A-Za-z_][A-Za-z0-9_]*=.*/.test(token);
}

const WRAPPERS = new Set([
  'sudo', 'nohup', 'command', 'nice', 'time', 'timeout',
  'strace', 'ltrace', 'taskset', 'ionice', 'setsid', 'stdbuf', 'xvfb-run',
]);

const WRAPPER_FLAGS_WITH_VALUE = new Set([
  '-n', '-p', '--adjustment',
  '-i', '-o', '-e', '--input', '--output', '--error',
  '-k', '--kill-after', '-s', '--signal',
]);

const SUDO_FLAGS_WITH_VALUE = new Set([
  '-u', '--user',
  '-g', '--group',
  '-h', '--host',
  '-p', '--prompt',
  '-C', '--close-from',
  '-R', '--chroot',
  '-D', '--chdir',
  '-r', '--role',
  '-t', '--type',
]);

const WRAPPER_FLAGS_WITH_VALUE_BY_WRAPPER = new Map([
  ['ionice', new Set(['-c', '--class', '--classdata'])],
  ['xvfb-run', new Set([
    '-e', '--error-file',
    '-f', '--auth-file',
    '-n', '--server-num',
    '-p', '--xauth-protocol',
    '-s', '--server-args',
  ])],
]);

const WRAPPERS_WITH_POSITIONAL_ARG = new Set(['timeout', 'taskset']);
const SHELL_CONTROL_TOKENS = new Set(['|', '||', '&&', ';', '&']);
const SHELL_GROUPING_TOKENS = new Set(['(', ')']);
const SHELL_PREFIX_BUILTINS = new Set(['set']);
const SHELL_PASSTHROUGH_BUILTINS = new Set(['exec']);

function skipToNextCommandBoundary(tokens, startIndex) {
  let i = startIndex;
  while (i < tokens.length) {
    const token = stripOuterQuotes(tokens[i].raw);
    if (SHELL_CONTROL_TOKENS.has(token)) {
      return i + 1;
    }
    i += 1;
  }
  return tokens.length;
}

function isSudoFlagWithValue(token) {
  if (SUDO_FLAGS_WITH_VALUE.has(token)) return true;
  return /^--(?:user|group|host|prompt|close-from|chroot|chdir|role|type)=/.test(token);
}

function findCommandToken(command, options) {
  const seekChromium = Boolean(options && options.seekChromium);
  const tokens = tokenizeCommand(command);
  let i = 0;

  while (i < tokens.length) {
    const raw = tokens[i].raw;
    const token = stripOuterQuotes(raw);

    if (SHELL_CONTROL_TOKENS.has(token)) {
      i += 1;
      continue;
    }
    if (SHELL_GROUPING_TOKENS.has(token)) {
      i += 1;
      continue;
    }
    if (token === '--') {
      i += 1;
      continue;
    }
    if (isAssignmentToken(token)) {
      i += 1;
      continue;
    }
    // `exec cmd` preserves the current segment's command position.
    if (SHELL_PASSTHROUGH_BUILTINS.has(token)) {
      i += 1;
      continue;
    }

    // `set -e; cmd` is a common shell prefix; skip to the next command segment.
    if (SHELL_PREFIX_BUILTINS.has(token)) {
      i = skipToNextCommandBoundary(tokens, i + 1);
      continue;
    }

    if (token === 'env') {
      const envFlagsWithValue = new Set(['-u', '--unset', '-S', '--split-string']);
      i += 1;
      while (i < tokens.length) {
        const envTok = stripOuterQuotes(tokens[i].raw);
        if (envTok === '--') {
          i += 1;
          break;
        }
        if (envFlagsWithValue.has(envTok)) {
          i += 2;
          continue;
        }
        if (envTok.startsWith('-') || isAssignmentToken(envTok)) {
          i += 1;
          continue;
        }
        break;
      }
      continue;
    }

    if (WRAPPERS.has(token)) {
      if (token === 'sudo') {
        i += 1;
        while (i < tokens.length) {
          const sudoTok = stripOuterQuotes(tokens[i].raw);
          if (sudoTok === '--') {
            i += 1;
            break;
          }
          if (isSudoFlagWithValue(sudoTok)) {
            // Long-form with "=" carries its value in the same token.
            if (sudoTok.includes('=')) {
              i += 1;
            } else {
              i += 2;
            }
            continue;
          }
          if (sudoTok.startsWith('-')) {
            i += 1;
            continue;
          }
          break;
        }
        continue;
      }
      // Wrappers that may take flag/value pairs before the real command.
      const wrapperUsesNumericPositional = token === 'nice';
      const wrapperUsesSinglePositional = WRAPPERS_WITH_POSITIONAL_ARG.has(token);
      const wrapperSpecificFlagsWithValue = WRAPPER_FLAGS_WITH_VALUE_BY_WRAPPER.get(token);
      let consumedPositional = false;
      i += 1;
      while (i < tokens.length) {
        const wTok = stripOuterQuotes(tokens[i].raw);
        if (wTok === '--') {
          i += 1;
          break;
        }
        if (
          WRAPPER_FLAGS_WITH_VALUE.has(wTok) ||
          (wrapperSpecificFlagsWithValue && wrapperSpecificFlagsWithValue.has(wTok))
        ) {
          i += 2;
          continue;
        }
        if (wTok.startsWith('-')) {
          i += 1;
          continue;
        }
        // nice can accept a bare numeric priority (e.g. `nice 5 cmd`).
        if (wrapperUsesNumericPositional && !consumedPositional && /^[-+]?\d+$/.test(wTok)) {
          i += 1;
          consumedPositional = true;
          continue;
        }
        // timeout takes duration as first positional argument before command.
        if (wrapperUsesSinglePositional && !consumedPositional) {
          i += 1;
          consumedPositional = true;
          continue;
        }
        break;
      }
      continue;
    }

    if (!seekChromium) {
      return tokens[i];
    }
    if (isChromiumBinary(stripOuterQuotes(tokens[i].raw))) {
      return tokens[i];
    }
    i = skipToNextCommandBoundary(tokens, i + 1);
  }
  return null;
}

function extractCommandToken(command) {
  if (typeof command !== 'string') return '';
  const token = findCommandToken(command);
  return token ? stripOuterQuotes(token.raw) : '';
}

function isChromiumCommandString(command) {
  const token = extractCommandToken(command);
  return isChromiumBinary(token);
}

const SHELL_BINARIES = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh']);

function isShellBinary(cmd) {
  if (typeof cmd !== 'string') return false;
  const basename = cmd.split('/').pop().split('\\').pop();
  return SHELL_BINARIES.has(basename);
}

// Detect if command is a wrapper binary (setsid, nohup, nice, etc.)
function isWrapperBinary(cmd) {
  if (typeof cmd !== 'string') return false;
  const basename = cmd.split('/').pop().split('\\').pop();
  return WRAPPERS.has(basename);
}

// Detect if command is the `env` binary
function isEnvBinary(cmd) {
  if (typeof cmd !== 'string') return false;
  const basename = cmd.split('/').pop().split('\\').pop();
  return basename === 'env';
}

const ENV_FLAGS_WITH_VALUE = new Set(['-u', '--unset', '-S', '--split-string']);

// For non-shell spawn('env', ['FOO=bar', 'chromium', ...]), skip env-specific
// KEY=VALUE assignments and flags, find the chromium binary, and inject
// --no-sandbox after it.
function patchEnvWrapperArgs(args) {
  if (!Array.isArray(args)) return args;
  if (args.some(a => String(a) === '--no-sandbox')) return args;
  let i = 0;
  while (i < args.length) {
    const arg = String(args[i]);
    if (arg === '--') {
      i += 1;
      break;
    }
    if (ENV_FLAGS_WITH_VALUE.has(arg)) {
      i += 2;
      continue;
    }
    if (arg.startsWith('-') || isAssignmentToken(arg)) {
      i += 1;
      continue;
    }
    // Found the actual command
    break;
  }
  if (i < args.length) {
    const command = String(args[i]);
    if (isChromiumBinary(command)) {
      const patched = args.slice();
      patched.splice(i + 1, 0, '--no-sandbox');
      return patched;
    }
    const nested = patchNestedWrapperInvocation(command, args.slice(i + 1));
    if (nested) {
      return args.slice(0, i + 1).concat(nested);
    }
  }
  return args;
}

// For non-shell spawn('wrapper', ['chromium', ...]), find the chromium binary
// in the args array and inject --no-sandbox after it.  Accepts the wrapper
// name so it can handle wrapper-specific positional arguments (nice numeric
// priority, timeout duration, taskset mask).
function patchWrapperArgs(wrapperName, args) {
  if (!Array.isArray(args)) return args;
  if (args.some(a => String(a) === '--no-sandbox')) return args;
  const basename = typeof wrapperName === 'string'
    ? wrapperName.split('/').pop().split('\\').pop()
    : '';
  const usesNumericPositional = basename === 'nice';
  const usesSinglePositional = WRAPPERS_WITH_POSITIONAL_ARG.has(basename);
  const wrapperSpecificFlags = WRAPPER_FLAGS_WITH_VALUE_BY_WRAPPER.get(basename);
  let consumedPositional = false;
  for (let i = 0; i < args.length; i++) {
    const arg = String(args[i]);
    if (arg === '--') {
      // After --, next token is the command (end of wrapper options)
      if (i + 1 < args.length) {
        const nextArg = String(args[i + 1]);
        if (isChromiumBinary(nextArg)) {
          const patched = args.slice();
          patched.splice(i + 2, 0, '--no-sandbox');
          return patched;
        }
        const nested = patchNestedWrapperInvocation(nextArg, args.slice(i + 2));
        if (nested) {
          return args.slice(0, i + 2).concat(nested);
        }
      }
      return args;
    }
    if (basename === 'sudo' && isSudoFlagWithValue(arg)) {
      if (!arg.includes('=')) {
        i += 1; // skip the value token for -u USER style flags
      }
      continue;
    }
    if (
      WRAPPER_FLAGS_WITH_VALUE.has(arg) ||
      (wrapperSpecificFlags && wrapperSpecificFlags.has(arg))
    ) {
      i += 1; // skip value
      continue;
    }
    if (arg.startsWith('-')) continue;
    if (usesNumericPositional && !consumedPositional && /^[-+]?\d+$/.test(arg)) {
      consumedPositional = true;
      continue;
    }
    if (usesSinglePositional && !consumedPositional) {
      consumedPositional = true;
      continue;
    }
    if (isChromiumBinary(arg)) {
      const patched = args.slice();
      patched.splice(i + 1, 0, '--no-sandbox');
      return patched;
    }
    const nested = patchNestedWrapperInvocation(arg, args.slice(i + 1));
    if (nested) {
      return args.slice(0, i + 1).concat(nested);
    }
    // First non-flag, non-positional, non-chromium arg: this is the actual command, stop.
    break;
  }
  return args;
}

function patchNestedWrapperInvocation(command, args) {
  if (isShellBinary(command)) return patchShellWrapperArgs(args);
  if (isEnvBinary(command)) return patchEnvWrapperArgs(args);
  if (isWrapperBinary(command)) return patchWrapperArgs(command, args);
  return null;
}

// Patch args for shell wrapper invocations like bash -c "chromium ..."
function patchShellWrapperArgs(args) {
  if (!Array.isArray(args)) return args;
  for (let i = 0; i < args.length; i++) {
    const arg = String(args[i]);
    // Match -c, -lc, -ic, etc. (shell execution flags)
    if (/^-\w*c\w*$/.test(arg) && i + 1 < args.length) {
      const cmdStr = args[i + 1];
      if (typeof cmdStr === 'string') {
        const injected = injectNoSandboxCommand(cmdStr);
        if (injected === cmdStr) break;
        const patched = args.slice();
        patched[i + 1] = injected;
        return patched;
      }
      break;
    }
  }
  return args;
}

function rewriteToken(command, token, replacement) {
  if (!token || token.raw === replacement) return command;
  return `${command.slice(0, token.index)}${replacement}${command.slice(token.index + token.raw.length)}`;
}

function rewriteQuotedToken(command, token, replacementInner) {
  if (!token) return command;
  let replacement = replacementInner;
  const raw = token.raw;
  const first = raw[0];
  const last = raw[raw.length - 1];
  if ((first === '"' || first === "'") && first === last) {
    replacement = `${first}${replacementInner}${first}`;
  }
  return rewriteToken(command, token, replacement);
}

function findSegmentEnd(tokens, startIndex) {
  let i = startIndex;
  while (i < tokens.length) {
    const token = stripOuterQuotes(tokens[i].raw);
    if (SHELL_CONTROL_TOKENS.has(token)) {
      break;
    }
    i += 1;
  }
  return i;
}

function findShellDashCArgToken(tokens, shellIndex, segmentEnd) {
  let j = shellIndex + 1;
  while (j < segmentEnd) {
    const arg = stripOuterQuotes(tokens[j].raw);
    if (/^-\w*c\w*$/.test(arg) && j + 1 < segmentEnd) {
      return tokens[j + 1];
    }
    if (arg === '--') {
      j += 1;
      continue;
    }
    if (arg.startsWith('-')) {
      j += 1;
      continue;
    }
    break;
  }
  return null;
}

function collectShellDashCReplacements(command) {
  const tokens = tokenizeCommand(command);
  const replacements = [];
  let i = 0;

  while (i < tokens.length) {
    const boundary = stripOuterQuotes(tokens[i].raw);
    if (SHELL_CONTROL_TOKENS.has(boundary)) {
      i += 1;
      continue;
    }
    const segmentEnd = findSegmentEnd(tokens, i);
    let j = i;

    while (j < segmentEnd) {
      const token = stripOuterQuotes(tokens[j].raw);
      if (SHELL_GROUPING_TOKENS.has(token) || token === '--') {
        j += 1;
        continue;
      }
      if (isAssignmentToken(token)) {
        j += 1;
        continue;
      }
      if (SHELL_PASSTHROUGH_BUILTINS.has(token)) {
        j += 1;
        continue;
      }
      if (SHELL_PREFIX_BUILTINS.has(token)) {
        // `set` modifies shell state; command position starts in next segment.
        j = segmentEnd;
        break;
      }

      if (token === 'env') {
        const envFlagsWithValue = new Set(['-u', '--unset', '-S', '--split-string']);
        j += 1;
        while (j < segmentEnd) {
          const envTok = stripOuterQuotes(tokens[j].raw);
          if (envTok === '--') {
            j += 1;
            break;
          }
          if (envFlagsWithValue.has(envTok)) {
            j += 2;
            continue;
          }
          if (envTok.startsWith('-') || isAssignmentToken(envTok)) {
            j += 1;
            continue;
          }
          break;
        }
        continue;
      }

      if (WRAPPERS.has(token)) {
        if (token === 'sudo') {
          j += 1;
          while (j < segmentEnd) {
            const sudoTok = stripOuterQuotes(tokens[j].raw);
            if (sudoTok === '--') {
              j += 1;
              break;
            }
            if (isSudoFlagWithValue(sudoTok)) {
              if (sudoTok.includes('=')) {
                j += 1;
              } else {
                j += 2;
              }
              continue;
            }
            if (sudoTok.startsWith('-')) {
              j += 1;
              continue;
            }
            break;
          }
          continue;
        }
        const wrapperUsesNumericPositional = token === 'nice';
        const wrapperUsesSinglePositional = WRAPPERS_WITH_POSITIONAL_ARG.has(token);
        const wrapperSpecificFlagsWithValue = WRAPPER_FLAGS_WITH_VALUE_BY_WRAPPER.get(token);
        let consumedPositional = false;
        j += 1;
        while (j < segmentEnd) {
          const wTok = stripOuterQuotes(tokens[j].raw);
          if (wTok === '--') {
            j += 1;
            break;
          }
          if (
            WRAPPER_FLAGS_WITH_VALUE.has(wTok) ||
            (wrapperSpecificFlagsWithValue && wrapperSpecificFlagsWithValue.has(wTok))
          ) {
            j += 2;
            continue;
          }
          if (wTok.startsWith('-')) {
            j += 1;
            continue;
          }
          if (wrapperUsesNumericPositional && !consumedPositional && /^[-+]?\d+$/.test(wTok)) {
            j += 1;
            consumedPositional = true;
            continue;
          }
          if (wrapperUsesSinglePositional && !consumedPositional) {
            j += 1;
            consumedPositional = true;
            continue;
          }
          break;
        }
        continue;
      }

      // Command position resolved for this segment.
      if (isShellBinary(token)) {
        const cmdToken = findShellDashCArgToken(tokens, j, segmentEnd);
        if (cmdToken) {
          const innerCommand = stripOuterQuotes(cmdToken.raw);
          const injected = injectNoSandboxCommand(innerCommand);
          if (injected !== innerCommand) {
            replacements.push({ token: cmdToken, replacementInner: injected });
          }
        }
      }
      break;
    }

    i = segmentEnd;
  }

  return replacements;
}

function injectViaShellDashC(command) {
  const replacements = collectShellDashCReplacements(command);
  if (replacements.length === 0) {
    return command;
  }
  replacements.sort((a, b) => b.token.index - a.token.index);
  let result = command;
  for (const replacement of replacements) {
    result = rewriteQuotedToken(result, replacement.token, replacement.replacementInner);
  }
  return result;
}

// Like findCommandToken with seekChromium, but returns ALL chromium command
// tokens across every shell segment rather than just the first.
function findAllChromiumTokens(command) {
  const tokens = tokenizeCommand(command);
  const results = [];
  let i = 0;

  while (i < tokens.length) {
    const raw = tokens[i].raw;
    const token = stripOuterQuotes(raw);

    if (SHELL_CONTROL_TOKENS.has(token)) { i += 1; continue; }
    if (SHELL_GROUPING_TOKENS.has(token)) { i += 1; continue; }
    if (token === '--') { i += 1; continue; }
    if (isAssignmentToken(token)) { i += 1; continue; }
    if (SHELL_PASSTHROUGH_BUILTINS.has(token)) { i += 1; continue; }
    if (SHELL_PREFIX_BUILTINS.has(token)) {
      i = skipToNextCommandBoundary(tokens, i + 1);
      continue;
    }

    if (token === 'env') {
      const envFlagsWithValue = new Set(['-u', '--unset', '-S', '--split-string']);
      i += 1;
      while (i < tokens.length) {
        const envTok = stripOuterQuotes(tokens[i].raw);
        if (envTok === '--') { i += 1; break; }
        if (envFlagsWithValue.has(envTok)) { i += 2; continue; }
        if (envTok.startsWith('-') || isAssignmentToken(envTok)) { i += 1; continue; }
        break;
      }
      continue;
    }

    if (WRAPPERS.has(token)) {
      if (token === 'sudo') {
        i += 1;
        while (i < tokens.length) {
          const sudoTok = stripOuterQuotes(tokens[i].raw);
          if (sudoTok === '--') { i += 1; break; }
          if (isSudoFlagWithValue(sudoTok)) {
            if (sudoTok.includes('=')) { i += 1; } else { i += 2; }
            continue;
          }
          if (sudoTok.startsWith('-')) { i += 1; continue; }
          break;
        }
        continue;
      }
      const wrapperUsesNumericPositional = token === 'nice';
      const wrapperUsesSinglePositional = WRAPPERS_WITH_POSITIONAL_ARG.has(token);
      const wrapperSpecificFlagsWithValue = WRAPPER_FLAGS_WITH_VALUE_BY_WRAPPER.get(token);
      let consumedPositional = false;
      i += 1;
      while (i < tokens.length) {
        const wTok = stripOuterQuotes(tokens[i].raw);
        if (wTok === '--') { i += 1; break; }
        if (
          WRAPPER_FLAGS_WITH_VALUE.has(wTok) ||
          (wrapperSpecificFlagsWithValue && wrapperSpecificFlagsWithValue.has(wTok))
        ) { i += 2; continue; }
        if (wTok.startsWith('-')) { i += 1; continue; }
        if (wrapperUsesNumericPositional && !consumedPositional && /^[-+]?\d+$/.test(wTok)) {
          i += 1; consumedPositional = true; continue;
        }
        if (wrapperUsesSinglePositional && !consumedPositional) {
          i += 1; consumedPositional = true; continue;
        }
        break;
      }
      continue;
    }

    // This is a command position token -- check if it's chromium
    if (isChromiumBinary(stripOuterQuotes(tokens[i].raw))) {
      // Check if --no-sandbox already present in this segment
      let hasNoSandbox = false;
      for (let j = i + 1; j < tokens.length; j++) {
        const t = stripOuterQuotes(tokens[j].raw);
        if (SHELL_CONTROL_TOKENS.has(t)) break;
        if (t === '--no-sandbox') { hasNoSandbox = true; break; }
      }
      if (!hasNoSandbox) {
        results.push(tokens[i]);
      }
    }
    i = skipToNextCommandBoundary(tokens, i + 1);
  }
  return results;
}

function injectNoSandboxCommand(command) {
  if (typeof command !== 'string') return command;
  const shellWrapped = injectViaShellDashC(command);
  if (shellWrapped !== command) return shellWrapped;

  // Find all chromium commands across all segments that need patching
  const chromiumTokens = findAllChromiumTokens(command);
  if (chromiumTokens.length === 0) return command;

  // Inject in reverse order to preserve earlier token indices
  let result = command;
  for (let k = chromiumTokens.length - 1; k >= 0; k--) {
    const tok = chromiumTokens[k];
    result = rewriteToken(result, tok, `${tok.raw} --no-sandbox`);
  }
  return result;
}

// Patch spawn
const originalSpawn = childProcess.spawn;
childProcess.spawn = function patchedSpawn(command, args, options) {
  const normalized = normalizeSpawnOverload(args, options);
  try {
    const isShellSpawn = Boolean(normalized.options && normalized.options.shell);
    if (isShellSpawn) {
      if (typeof command === 'string') {
        command = injectNoSandboxCommand(command);
      } else if (isChromiumBinary(command)) {
        normalized.args = injectNoSandbox(normalized.args);
      }
    } else if (isChromiumBinary(command)) {
      normalized.args = injectNoSandbox(normalized.args);
    } else if (isShellBinary(command)) {
      normalized.args = patchShellWrapperArgs(normalized.args);
    } else if (isEnvBinary(command)) {
      normalized.args = patchEnvWrapperArgs(normalized.args);
    } else if (isWrapperBinary(command)) {
      normalized.args = patchWrapperArgs(command, normalized.args);
    }
  } catch (e) {
    emitPatchWarning('spawn', e);
    normalized.args = fallbackInjectArgs(command, normalized.args);
  }
  return originalSpawn.call(this, command, normalized.args, normalized.options);
};

// Patch spawnSync
const originalSpawnSync = childProcess.spawnSync;
childProcess.spawnSync = function patchedSpawnSync(command, args, options) {
  const normalized = normalizeSpawnOverload(args, options);
  try {
    const isShellSpawn = Boolean(normalized.options && normalized.options.shell);
    if (isShellSpawn) {
      if (typeof command === 'string') {
        command = injectNoSandboxCommand(command);
      } else if (isChromiumBinary(command)) {
        normalized.args = injectNoSandbox(normalized.args);
      }
    } else if (isChromiumBinary(command)) {
      normalized.args = injectNoSandbox(normalized.args);
    } else if (isShellBinary(command)) {
      normalized.args = patchShellWrapperArgs(normalized.args);
    } else if (isEnvBinary(command)) {
      normalized.args = patchEnvWrapperArgs(normalized.args);
    } else if (isWrapperBinary(command)) {
      normalized.args = patchWrapperArgs(command, normalized.args);
    }
  } catch (e) {
    emitPatchWarning('spawnSync', e);
    normalized.args = fallbackInjectArgs(command, normalized.args);
  }
  return originalSpawnSync.call(this, command, normalized.args, normalized.options);
};

// Patch execFile (used by some tools)
// Handles all overloads: execFile(file[, args][, options][, callback])
//
// Coupling: patchedExec (below) sets _scodeExecPatched on the options object
// before calling the original exec, which may internally call execFile. The
// flag prevents double-patching the command. It is deleted immediately after
// detection so it does not leak into user-visible options.
const originalExecFile = childProcess.execFile;
childProcess.execFile = function patchedExecFile(file, args, options, callback) {
  const normalized = normalizeExecFileOverload(args, options, callback);
  let fromPatchedExec = false;
  try {
    fromPatchedExec = Boolean(
      normalized.options && normalized.options._scodeExecPatched === true
    );
    if (fromPatchedExec) {
      delete normalized.options._scodeExecPatched;
    }
    if (!fromPatchedExec) {
      if (isChromiumBinary(file)) {
        normalized.args = injectNoSandbox(normalized.args);
      } else if (isShellBinary(file)) {
        normalized.args = patchShellWrapperArgs(normalized.args);
      } else if (isEnvBinary(file)) {
        normalized.args = patchEnvWrapperArgs(normalized.args);
      } else if (isWrapperBinary(file)) {
        normalized.args = patchWrapperArgs(file, normalized.args);
      }
    }
  } catch (e) {
    emitPatchWarning('execFile', e);
    if (!fromPatchedExec) {
      normalized.args = fallbackInjectArgs(file, normalized.args);
    }
  }
  return originalExecFile.call(
    this,
    file,
    normalized.args,
    normalized.options,
    normalized.callback
  );
};

// Patch execFileSync
const originalExecFileSync = childProcess.execFileSync;
childProcess.execFileSync = function patchedExecFileSync(file, args, options) {
  const normalized = normalizeExecFileSyncOverload(args, options);
  try {
    if (isChromiumBinary(file)) {
      normalized.args = injectNoSandbox(normalized.args);
    } else if (isShellBinary(file)) {
      normalized.args = patchShellWrapperArgs(normalized.args);
    } else if (isEnvBinary(file)) {
      normalized.args = patchEnvWrapperArgs(normalized.args);
    } else if (isWrapperBinary(file)) {
      normalized.args = patchWrapperArgs(file, normalized.args);
    }
  } catch (e) {
    emitPatchWarning('execFileSync', e);
    normalized.args = fallbackInjectArgs(file, normalized.args);
  }
  return originalExecFileSync.call(this, file, normalized.args, normalized.options);
};

// Patch exec
const originalExec = childProcess.exec;
childProcess.exec = function patchedExec(command, options, callback) {
  const normalized = normalizeExecOverload(options, callback);
  try {
    if (typeof command === 'string') {
      command = injectNoSandboxCommand(command);
    }
  } catch (e) {
    emitPatchWarning('exec', e);
  }
  const execOptions =
    normalized.options && typeof normalized.options === 'object'
      ? { ...normalized.options, _scodeExecPatched: true }
      : { _scodeExecPatched: true };
  return originalExec.call(this, command, execOptions, normalized.callback);
};

// Patch execSync
const originalExecSync = childProcess.execSync;
childProcess.execSync = function patchedExecSync(command, options) {
  try {
    if (typeof command === 'string') {
      command = injectNoSandboxCommand(command);
    }
  } catch (e) {
    emitPatchWarning('execSync', e);
  }
  return originalExecSync.call(this, command, options);
};
