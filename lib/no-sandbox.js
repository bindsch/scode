// scode no-sandbox preload module
// Loaded via NODE_OPTIONS="--require=/path/to/no-sandbox.js"
// Patches child_process.spawn to inject --no-sandbox when launching Chromium.
// Only activates when SCODE_SANDBOXED=1 is set.
//
// Note: bare `return` statements below are valid because Node's --require
// wraps the file in a function scope (CommonJS module wrapper).

'use strict';

// ===== Pure constants and functions (above guards for testability) =====

// Patterns that identify a Chromium binary
const CHROMIUM_PATTERNS = [
  /^(?:google[ -])?chrome(?:-(?:stable|beta|dev|canary))?(?:\.(?:exe|cmd|bat))?$/i,
  /^chromium(?:-browser)?(?:\.(?:exe|cmd|bat))?$/i,
  /^brave(?: browser|-browser(?:-(?:stable|beta|nightly))?)?(?:\.(?:exe|cmd|bat))?$/i,
  /^(?:msedge|microsoft[ -]edge)(?:-(?:stable|beta|dev|canary))?(?:\.(?:exe|cmd|bat))?$/i,
  /^(?:(?:chrome|chromium)-)?headless[_-]?shell(?:\.(?:exe|cmd|bat))?$/i,
];
const ELECTRON_BINARY_NAMES = new Set(['electron', 'electron.exe', 'electron.cmd', 'electron.bat']);

const WRAPPERS = new Set([
  'sudo', 'nohup', 'command', 'nice', 'time', 'timeout',
  'strace', 'ltrace', 'taskset', 'ionice', 'setsid', 'stdbuf', 'xvfb-run',
]);

const WRAPPER_FLAGS_WITH_VALUE = new Set([
  '-n', '--adjustment',
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
  ['time', new Set(['-f', '--format'])],
  ['xvfb-run', new Set([
    '-e', '--error-file',
    '-f', '--auth-file',
    '-n', '--server-num',
    '-p', '--xauth-protocol',
    '-s', '--server-args',
  ])],
]);

const SHELL_CONTROL_TOKENS = new Set(['|', '||', '&&', ';', '&', '\n', '\r\n']);
const SHELL_GROUPING_TOKENS = new Set(['(', ')', '{', '}']);
const SHELL_PREFIX_BUILTINS = new Set(['set']);
const SHELL_PASSTHROUGH_BUILTINS = new Set(['exec', '!']);
const SHELL_KEYWORD_TOKENS = new Set([
  'if', 'then', 'elif', 'else', 'fi', 'while', 'until', 'do', 'done', 'esac',
]);
const SHELL_BINARIES = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh']);
const ENV_FLAGS_WITH_VALUE = new Set([
  '-u', '--unset', '-S', '--split-string', '-C', '--chdir', '-a', '--argv0',
]);
const ENV_SPLIT_STRING_FLAGS = new Set(['-S', '--split-string']);

function tokenizeCommand(command) {
  if (typeof command !== 'string') return [];
  const tokens = [];
  const isHorizontalSpace = ch => /[ \t\f\v]/.test(ch);
  const isControlStart = ch => ';|&(){}'.includes(ch);
  let i = 0;

  while (i < command.length) {
    if (isHorizontalSpace(command[i])) {
      i += 1;
      continue;
    }
    if (command[i] === '\r' && command[i + 1] === '\n') {
      tokens.push({ raw: '\r\n', index: i });
      i += 2;
      continue;
    }
    if (command[i] === '\n' || command[i] === '\r') {
      tokens.push({ raw: command[i], index: i });
      i += 1;
      continue;
    }
    if (command[i] === '#') {
      // A shell comment begins only where a new word could begin.
      while (i < command.length && command[i] !== '\n' && command[i] !== '\r') i += 1;
      continue;
    }
    if (isControlStart(command[i])) {
      const pair = command.slice(i, i + 2);
      if (pair === '&&' || pair === '||') {
        tokens.push({ raw: pair, index: i });
        i += 2;
      } else {
        tokens.push({ raw: command[i], index: i });
        i += 1;
      }
      continue;
    }

    const start = i;
    let quote = '';
    while (i < command.length) {
      const ch = command[i];
      if (quote === "'") {
        i += 1;
        if (ch === "'") quote = '';
        continue;
      }
      if (quote === '"') {
        if (ch === '\\' && i + 1 < command.length) {
          i += 2;
          continue;
        }
        i += 1;
        if (ch === '"') quote = '';
        continue;
      }
      if (ch === '\\' && i + 1 < command.length) {
        i += 2;
        continue;
      }
      if (ch === "'" || ch === '"') {
        quote = ch;
        i += 1;
        continue;
      }
      if (isHorizontalSpace(ch) || ch === '\n' || ch === '\r' || isControlStart(ch)) break;
      i += 1;
    }
    tokens.push({ raw: command.slice(start, i), index: start });
  }
  return tokens;
}

function commandBasename(command) {
  if (typeof command !== 'string') return '';
  return stripEscapedOuterQuotes(stripOuterQuotes(command)).split('/').pop().split('\\').pop();
}

function wrapperNameFor(command) {
  const basename = commandBasename(command);
  return WRAPPERS.has(basename) ? basename : '';
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

function parseEnvSplitStringOption(token) {
  if (typeof token !== 'string') return null;
  let prefix;
  let value;
  if (token.startsWith('--split-string=')) {
    prefix = '--split-string=';
    value = token.slice(prefix.length);
  } else if (token.startsWith('-S') && token !== '-S') {
    prefix = '-S';
    value = token.slice(prefix.length);
  } else {
    return null;
  }
  const quote = value.length >= 2 && (value[0] === '"' || value[0] === "'") && value.at(-1) === value[0]
    ? value[0]
    : '';
  return {
    prefix,
    quote,
    value: quote ? value.slice(1, -1) : value,
  };
}

function formatEnvSplitStringOption(parsed, value) {
  return `${parsed.prefix}${parsed.quote}${value}${parsed.quote}`;
}

function isChromiumBinary(cmd) {
  if (Buffer.isBuffer(cmd)) {
    cmd = cmd.toString('utf8');
  }
  if (typeof cmd !== 'string') return false;
  cmd = stripEscapedOuterQuotes(stripOuterQuotes(cmd.trim()));
  const basename = cmd.split('/').pop().split('\\').pop();
  const lowerBasename = basename.toLowerCase();
  if (ELECTRON_BINARY_NAMES.has(lowerBasename)) {
    return true;
  }
  return CHROMIUM_PATTERNS.some(p => p.test(basename));
}

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

function skipToNextCommandBoundary(tokens, startIndex) {
  let i = startIndex;
  while (i < tokens.length) {
    const token = stripOuterQuotes(tokens[i].raw);
    if (SHELL_CONTROL_TOKENS.has(token) || token === ')') {
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

function isTimeoutDurationToken(token) {
  return /^([0-9]+(?:\.[0-9]+)?|\.[0-9]+)[smhd]?$/i.test(token) || /^inf(?:inity)?$/i.test(token);
}

function isTasksetMaskToken(token) {
  if (/^0x[0-9a-f]+$/i.test(token)) return true;
  if (/^[0-9]+$/.test(token)) return true;
  return /^[0-9]+(?:-[0-9]+)?(?:,[0-9]+(?:-[0-9]+)?)*$/.test(token);
}

function shouldConsumeWrapperPositional(wrapperName, token) {
  if (wrapperName === 'nice') {
    return /^[-+]?\d+$/.test(token);
  }
  if (wrapperName === 'timeout') {
    return isTimeoutDurationToken(token);
  }
  if (wrapperName === 'taskset') {
    return isTasksetMaskToken(token);
  }
  return false;
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
    if (SHELL_KEYWORD_TOKENS.has(token)) {
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

    if (isEnvBinary(token)) {
      i += 1;
      while (i < tokens.length) {
        const envTok = stripOuterQuotes(tokens[i].raw);
        if (envTok === '--') {
          i += 1;
          break;
        }
        if (parseEnvSplitStringOption(envTok)) {
          i += 1;
          continue;
        }
        if (ENV_FLAGS_WITH_VALUE.has(envTok)) {
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

    const wrapperName = wrapperNameFor(token);
    if (wrapperName) {
      if (wrapperName === 'sudo') {
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
      const wrapperSpecificFlagsWithValue = WRAPPER_FLAGS_WITH_VALUE_BY_WRAPPER.get(wrapperName);
      let consumedPositional = false;
      i += 1;
      while (i < tokens.length) {
        const wTok = stripOuterQuotes(tokens[i].raw);
        if (wTok === '--') {
          i += 1;
          if (
            i < tokens.length &&
            (wrapperName === 'timeout' || wrapperName === 'taskset') &&
            shouldConsumeWrapperPositional(wrapperName, stripOuterQuotes(tokens[i].raw))
          ) {
            i += 1;
          }
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
        if (!consumedPositional && shouldConsumeWrapperPositional(wrapperName, wTok)) {
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
  if (first === "'" && first === last) {
    // POSIX single quotes cannot contain another single quote. Re-quote the
    // complete argument using the standard '\'' boundary sequence.
    replacement = shellEscapeArg(replacementInner);
  } else if (first === '"' && first === last) {
    replacement = `${first}${replacementInner}${first}`;
  } else if (/[ \t\r\n\f\v;|&()]/.test(replacementInner)) {
    // Keep rewritten values as one shell argument when the original token was unquoted.
    replacement = shellEscapeArg(replacementInner);
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

function isShellDashCFlag(token) {
  return /^-\w*c\w*$/.test(token);
}

function findShellDashCArgToken(tokens, shellIndex, segmentEnd) {
  let j = shellIndex + 1;
  while (j < segmentEnd) {
    const arg = stripOuterQuotes(tokens[j].raw);
    if (isShellDashCFlag(arg) && j + 1 < segmentEnd) {
      // POSIX shells accept an option delimiter after -c, so both
      // `shell -c "cmd"` and `shell -c -- "cmd"` execute cmd.
      const commandIndex = stripOuterQuotes(tokens[j + 1].raw) === '--'
        ? j + 2
        : j + 1;
      return commandIndex < segmentEnd ? tokens[commandIndex] : null;
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
      if (SHELL_KEYWORD_TOKENS.has(token)) {
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

      if (isEnvBinary(token)) {
        j += 1;
        while (j < segmentEnd) {
          const envTok = stripOuterQuotes(tokens[j].raw);
          if (envTok === '--') {
            j += 1;
            break;
          }
          if (parseEnvSplitStringOption(envTok)) {
            j += 1;
            continue;
          }
          if (ENV_FLAGS_WITH_VALUE.has(envTok)) {
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

      const wrapperName = wrapperNameFor(token);
      if (wrapperName) {
        if (wrapperName === 'sudo') {
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
        const wrapperSpecificFlagsWithValue = WRAPPER_FLAGS_WITH_VALUE_BY_WRAPPER.get(wrapperName);
        let consumedPositional = false;
        j += 1;
        while (j < segmentEnd) {
          const wTok = stripOuterQuotes(tokens[j].raw);
          if (wTok === '--') {
            j += 1;
            if (
              j < segmentEnd &&
              (wrapperName === 'timeout' || wrapperName === 'taskset') &&
              shouldConsumeWrapperPositional(wrapperName, stripOuterQuotes(tokens[j].raw))
            ) {
              j += 1;
            }
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
          if (!consumedPositional && shouldConsumeWrapperPositional(wrapperName, wTok)) {
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

function collectEnvSplitStringReplacements(command) {
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
      if (SHELL_KEYWORD_TOKENS.has(token)) {
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
        j = segmentEnd;
        break;
      }

      if (isEnvBinary(token)) {
        j += 1;
        while (j < segmentEnd) {
          const envTok = stripOuterQuotes(tokens[j].raw);
          if (envTok === '--') {
            j += 1;
            break;
          }
          const inlineSplit = parseEnvSplitStringOption(envTok);
          if (inlineSplit) {
            const injectedSplit = injectNoSandboxCommand(inlineSplit.value);
            if (injectedSplit !== inlineSplit.value) {
              replacements.push({
                token: tokens[j],
                replacementRaw: formatEnvSplitStringOption(inlineSplit, injectedSplit),
              });
            }
            j += 1;
            continue;
          }
          if (ENV_SPLIT_STRING_FLAGS.has(envTok) && j + 1 < segmentEnd) {
            const splitToken = tokens[j + 1];
            const splitCommand = stripOuterQuotes(splitToken.raw);
            const injectedSplit = injectNoSandboxCommand(splitCommand);
            if (injectedSplit !== splitCommand) {
              replacements.push({ token: splitToken, replacementInner: injectedSplit });
            }
            j += 2;
            continue;
          }
          if (ENV_FLAGS_WITH_VALUE.has(envTok)) {
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

      const wrapperName = wrapperNameFor(token);
      if (wrapperName) {
        if (wrapperName === 'sudo') {
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
        const wrapperSpecificFlagsWithValue = WRAPPER_FLAGS_WITH_VALUE_BY_WRAPPER.get(wrapperName);
        let consumedPositional = false;
        j += 1;
        while (j < segmentEnd) {
          const wTok = stripOuterQuotes(tokens[j].raw);
          if (wTok === '--') {
            j += 1;
            if (
              j < segmentEnd &&
              (wrapperName === 'timeout' || wrapperName === 'taskset') &&
              shouldConsumeWrapperPositional(wrapperName, stripOuterQuotes(tokens[j].raw))
            ) {
              j += 1;
            }
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
          if (!consumedPositional && shouldConsumeWrapperPositional(wrapperName, wTok)) {
            j += 1;
            consumedPositional = true;
            continue;
          }
          break;
        }
        continue;
      }

      break;
    }

    i = segmentEnd;
  }

  return replacements;
}

function injectViaEnvSplitString(command) {
  const replacements = collectEnvSplitStringReplacements(command);
  if (replacements.length === 0) {
    return command;
  }
  replacements.sort((a, b) => b.token.index - a.token.index);
  let result = command;
  for (const replacement of replacements) {
    result = replacement.replacementRaw
      ? rewriteToken(result, replacement.token, replacement.replacementRaw)
      : rewriteQuotedToken(result, replacement.token, replacement.replacementInner);
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
    if (SHELL_KEYWORD_TOKENS.has(token)) { i += 1; continue; }
    if (token === '--') { i += 1; continue; }
    if (isAssignmentToken(token)) { i += 1; continue; }
    if (SHELL_PASSTHROUGH_BUILTINS.has(token)) { i += 1; continue; }
    if (SHELL_PREFIX_BUILTINS.has(token)) {
      i = skipToNextCommandBoundary(tokens, i + 1);
      continue;
    }

    if (isEnvBinary(token)) {
      i += 1;
      while (i < tokens.length) {
        const envTok = stripOuterQuotes(tokens[i].raw);
        if (envTok === '--') { i += 1; break; }
        if (parseEnvSplitStringOption(envTok)) { i += 1; continue; }
        if (ENV_FLAGS_WITH_VALUE.has(envTok)) { i += 2; continue; }
        if (envTok.startsWith('-') || isAssignmentToken(envTok)) { i += 1; continue; }
        break;
      }
      continue;
    }

    const wrapperName = wrapperNameFor(token);
    if (wrapperName) {
      if (wrapperName === 'sudo') {
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
      const wrapperSpecificFlagsWithValue = WRAPPER_FLAGS_WITH_VALUE_BY_WRAPPER.get(wrapperName);
      let consumedPositional = false;
      i += 1;
      while (i < tokens.length) {
        const wTok = stripOuterQuotes(tokens[i].raw);
        if (wTok === '--') {
          i += 1;
          if (
            i < tokens.length &&
            (wrapperName === 'timeout' || wrapperName === 'taskset') &&
            shouldConsumeWrapperPositional(wrapperName, stripOuterQuotes(tokens[i].raw))
          ) {
            i += 1;
          }
          break;
        }
        if (
          WRAPPER_FLAGS_WITH_VALUE.has(wTok) ||
          (wrapperSpecificFlagsWithValue && wrapperSpecificFlagsWithValue.has(wTok))
        ) { i += 2; continue; }
        if (wTok.startsWith('-')) { i += 1; continue; }
        if (!consumedPositional && shouldConsumeWrapperPositional(wrapperName, wTok)) {
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
  if (hasUnsupportedShellSyntax(command)) return command;
  let result = injectViaShellDashC(command);
  result = injectViaEnvSplitString(result);

  // Find all chromium commands across all segments that need patching
  const chromiumTokens = findAllChromiumTokens(result);
  if (chromiumTokens.length === 0) return result;

  // Inject in reverse order to preserve earlier token indices
  for (let k = chromiumTokens.length - 1; k >= 0; k--) {
    const tok = chromiumTokens[k];
    result = rewriteToken(result, tok, `${tok.raw} --no-sandbox`);
  }
  return result;
}

// Command substitutions and heredocs require a real shell AST. Rewriting a
// partial parse can change program meaning, so preserve these commands exactly.
function hasUnsupportedShellSyntax(command) {
  let quote = '';
  for (let i = 0; i < command.length; i += 1) {
    const ch = command[i];
    if (quote === "'") {
      if (ch === "'") quote = '';
      continue;
    }
    if (ch === '\\') {
      i += 1;
      continue;
    }
    if (ch === '"') {
      quote = quote === '"' ? '' : '"';
      continue;
    }
    if (!quote && ch === "'") {
      quote = "'";
      continue;
    }
    if (ch === '`' || (ch === '$' && command[i + 1] === '(')) return true;
    if (!quote && ch === '<' && command[i + 1] === '<') return true;
  }
  return false;
}

// ===== Test export (no-op in production --require mode) =====

if (typeof module !== 'undefined' && module.exports && process.env.SCODE_TEST === '1') {
  module.exports = {
    tokenizeCommand,
    stripOuterQuotes,
    stripEscapedOuterQuotes,
    isChromiumBinary,
    isShellBinary,
    isEnvBinary,
    isWrapperBinary,
    findCommandToken,
    injectNoSandboxCommand,
    patchEnvWrapperArgs,
    patchWrapperArgs,
  };
}

// ===== Production guards =====

if (process.env.SCODE_SANDBOXED !== '1') {
  return;
}

// Guard against double-loading (e.g. multiple --require entries)
const SCODE_PATCH_GUARD = Symbol.for('dev.scode.no-sandbox.loaded.v1');
if (global[SCODE_PATCH_GUARD]) {
  return;
}
global[SCODE_PATCH_GUARD] = true;

// ===== Runtime: monkey-patch child_process =====

const childProcess = require('child_process');

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

// For non-shell spawn('env', ['FOO=bar', 'chromium', ...]), skip env-specific
// KEY=VALUE assignments and flags, find the chromium binary, and inject
// --no-sandbox after it.
function patchEnvWrapperArgs(args) {
  if (!Array.isArray(args)) return args;
  let i = 0;
  while (i < args.length) {
    const arg = String(args[i]);
    if (arg === '--') {
      i += 1;
      break;
    }
    const inlineSplit = parseEnvSplitStringOption(arg);
    if (inlineSplit) {
      const injectedSplit = injectNoSandboxCommand(inlineSplit.value);
      if (injectedSplit !== inlineSplit.value) {
        const patched = args.slice();
        patched[i] = formatEnvSplitStringOption(inlineSplit, injectedSplit);
        return patched;
      }
      i += 1;
      continue;
    }
    if (ENV_SPLIT_STRING_FLAGS.has(arg)) {
      if (i + 1 >= args.length) {
        i += 1;
        continue;
      }
      const splitCommand = String(args[i + 1]);
      const injectedSplit = injectNoSandboxCommand(splitCommand);
      if (injectedSplit !== splitCommand) {
        const patched = args.slice();
        patched[i + 1] = injectedSplit;
        return patched;
      }
      i += 2;
      continue;
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
      if (args.slice(i + 1).some(a => String(a) === '--no-sandbox')) return args;
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
  const basename = typeof wrapperName === 'string'
    ? wrapperName.split('/').pop().split('\\').pop()
    : '';
  const wrapperSpecificFlags = WRAPPER_FLAGS_WITH_VALUE_BY_WRAPPER.get(basename);
  let consumedPositional = false;
  for (let i = 0; i < args.length; i++) {
    const arg = String(args[i]);
    if (arg === '--') {
      // timeout/taskset retain their required duration/mask after --.
      let commandIndex = i + 1;
      if (
        commandIndex < args.length &&
        (basename === 'timeout' || basename === 'taskset') &&
        shouldConsumeWrapperPositional(basename, String(args[commandIndex]))
      ) {
        commandIndex += 1;
      }
      if (commandIndex < args.length) {
        const nextArg = String(args[commandIndex]);
        if (isChromiumBinary(nextArg)) {
          if (args.slice(commandIndex + 1).some(a => String(a) === '--no-sandbox')) return args;
          const patched = args.slice();
          patched.splice(commandIndex + 1, 0, '--no-sandbox');
          return patched;
        }
        const nested = patchNestedWrapperInvocation(nextArg, args.slice(commandIndex + 1));
        if (nested) {
          return args.slice(0, commandIndex + 1).concat(nested);
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
    if (!consumedPositional && shouldConsumeWrapperPositional(basename, arg)) {
      consumedPositional = true;
      continue;
    }
    if (isChromiumBinary(arg)) {
      if (args.slice(i + 1).some(a => String(a) === '--no-sandbox')) return args;
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
    if (isShellDashCFlag(arg) && i + 1 < args.length) {
      const commandIndex = String(args[i + 1]) === '--' ? i + 2 : i + 1;
      if (commandIndex >= args.length) break;
      const cmdStr = args[commandIndex];
      if (typeof cmdStr === 'string') {
        const injected = injectNoSandboxCommand(cmdStr);
        if (injected === cmdStr) break;
        const patched = args.slice();
        patched[commandIndex] = injected;
        return patched;
      }
      break;
    }
  }
  return args;
}

function patchSpawnLikeArgs(command, args) {
  if (isChromiumBinary(command)) {
    return injectNoSandbox(args);
  }
  if (isShellBinary(command)) {
    return patchShellWrapperArgs(args);
  }
  if (isEnvBinary(command)) {
    return patchEnvWrapperArgs(args);
  }
  if (isWrapperBinary(command)) {
    return patchWrapperArgs(command, args);
  }
  return args;
}

function shellEscapeArg(arg) {
  const s = String(arg);
  if (s.length === 0) return "''";
  return `'${s.replace(/'/g, `'\"'\"'`)}'`;
}

function isSimpleShellWord(command) {
  return typeof command === 'string' && !/[ \t\r\n\f\v;|&()]/.test(command);
}

function mergeShellCommandAndArgs(command, args) {
  if (!isSimpleShellWord(command) || !Array.isArray(args) || args.length === 0) {
    return { command, args, merged: false };
  }
  return {
    command: [command, ...args.map(shellEscapeArg)].join(' '),
    args: [],
    merged: true
  };
}

// Patch spawn
const originalSpawn = childProcess.spawn;
childProcess.spawn = function patchedSpawn(command, args, options) {
  const normalized = normalizeSpawnOverload(args, options);
  try {
    const isShellSpawn = Boolean(normalized.options && normalized.options.shell);
    let shouldPatchArgs = true;
    if (isShellSpawn) {
      if (typeof command === 'string') {
        const merged = mergeShellCommandAndArgs(command, normalized.args);
        const injectedCommand = injectNoSandboxCommand(merged.command);
        if (injectedCommand !== merged.command) {
          command = injectedCommand;
          if (merged.merged) normalized.args = merged.args;
        }
        // shell:true already exposes the combined command to the tokenizer.
        // Preserve unrelated command/args byte-for-byte and never patch twice.
        shouldPatchArgs = false;
      }
    }
    if (shouldPatchArgs) {
      normalized.args = patchSpawnLikeArgs(command, normalized.args);
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
    let shouldPatchArgs = true;
    if (isShellSpawn) {
      if (typeof command === 'string') {
        const merged = mergeShellCommandAndArgs(command, normalized.args);
        const injectedCommand = injectNoSandboxCommand(merged.command);
        if (injectedCommand !== merged.command) {
          command = injectedCommand;
          if (merged.merged) normalized.args = merged.args;
        }
        // shell:true already exposes the combined command to the tokenizer.
        // Preserve unrelated command/args byte-for-byte and never patch twice.
        shouldPatchArgs = false;
      }
    }
    if (shouldPatchArgs) {
      normalized.args = patchSpawnLikeArgs(command, normalized.args);
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
