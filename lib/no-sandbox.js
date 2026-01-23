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
  const tokenRegex = /"([^"\\]|\\.)*"|'[^']*'|\S+/g;
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

function isAssignmentToken(token) {
  return /^[A-Za-z_][A-Za-z0-9_]*=.*/.test(token);
}

const WRAPPERS = new Set([
  'sudo', 'nohup', 'command', 'nice', 'time', 'timeout',
  'strace', 'ltrace', 'taskset', 'ionice', 'setsid', 'stdbuf',
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
]);

const WRAPPERS_WITH_POSITIONAL_ARG = new Set(['timeout', 'taskset']);

function isSudoFlagWithValue(token) {
  if (SUDO_FLAGS_WITH_VALUE.has(token)) return true;
  return /^--(?:user|group|host|prompt|close-from|chroot|chdir|role|type)=/.test(token);
}

function findCommandToken(command) {
  const tokens = tokenizeCommand(command);
  const shellControls = new Set(['|', '||', '&&', ';', '&']);
  const shellGrouping = new Set(['(', ')']);
  let i = 0;

  while (i < tokens.length) {
    const raw = tokens[i].raw;
    const token = stripOuterQuotes(raw);

    if (shellControls.has(token)) return null;
    if (shellGrouping.has(token)) {
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

    return tokens[i];
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
  if (i < args.length && isChromiumBinary(String(args[i]))) {
    const patched = args.slice();
    patched.splice(i + 1, 0, '--no-sandbox');
    return patched;
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
  const usesNumericPositional = basename === 'nice';
  const usesSinglePositional = WRAPPERS_WITH_POSITIONAL_ARG.has(basename);
  const wrapperSpecificFlags = WRAPPER_FLAGS_WITH_VALUE_BY_WRAPPER.get(basename);
  let consumedPositional = false;
  for (let i = 0; i < args.length; i++) {
    const arg = String(args[i]);
    if (arg === '--') continue;
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
    // First non-flag, non-positional, non-chromium arg: this is the actual command, stop
    break;
  }
  return args;
}

// Patch args for shell wrapper invocations like bash -c "chromium ..."
function patchShellWrapperArgs(args) {
  if (!Array.isArray(args)) return args;
  for (let i = 0; i < args.length; i++) {
    const arg = String(args[i]);
    // Match -c, -lc, -ic, etc. (shell execution flags)
    if (/^-\w*c$/.test(arg) && i + 1 < args.length) {
      const cmdStr = args[i + 1];
      if (typeof cmdStr === 'string' && isChromiumCommandString(cmdStr)) {
        const patched = args.slice();
        patched[i + 1] = injectNoSandboxCommand(cmdStr);
        return patched;
      }
      break;
    }
  }
  return args;
}

function injectNoSandboxCommand(command) {
  if (typeof command !== 'string') return command;
  if (/(^|\s)--no-sandbox(\s|$)/.test(command)) return command;
  const commandToken = findCommandToken(command);
  if (!commandToken) return command;
  if (!isChromiumBinary(stripOuterQuotes(commandToken.raw))) return command;
  const insertAt = commandToken.index + commandToken.raw.length;
  return `${command.slice(0, insertAt)} --no-sandbox${command.slice(insertAt)}`;
}

// Patch spawn
const originalSpawn = childProcess.spawn;
childProcess.spawn = function patchedSpawn(command, args, options) {
  const normalized = normalizeSpawnOverload(args, options);
  try {
    const isShellSpawn = Boolean(normalized.options && normalized.options.shell);
    if (isShellSpawn) {
      if (typeof command === 'string' && isChromiumCommandString(command)) {
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
      if (typeof command === 'string' && isChromiumCommandString(command)) {
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
    if (isChromiumCommandString(command)) {
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
    if (isChromiumCommandString(command)) {
      command = injectNoSandboxCommand(command);
    }
  } catch (e) {
    emitPatchWarning('execSync', e);
  }
  return originalExecSync.call(this, command, options);
};
