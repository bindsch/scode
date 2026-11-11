'use strict';

const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const { permits } = require('./policy_model');
const { parseProfile, seatbelt, parseMounts, bubblewrap } = require('./policy_evaluators');

const [launcherSource, temporary, selection = 'matrix'] = process.argv.slice(2);
const root = fs.realpathSync(temporary);
function file(name, executable = false) {
  fs.mkdirSync(path.dirname(name), { recursive: true });
  fs.writeFileSync(name, executable ? '#!/bin/sh\nexit 0\n' : 'synthetic-fixture\n');
  if (executable) fs.chmodSync(name, 0o755);
  return name;
}

function fixture(hops, targetKind, builtin = '.aws') {
  const home = `${root}/${builtin.slice(1)}-${hops}-${targetKind}`;
  const nestedProject = targetKind.startsWith('nested-project');
  const projectParent = `${home}/${hops === 0 ? builtin : '.codex/aws'}`;
  const project = nestedProject ? `${projectParent}/${targetKind.endsWith('-deep') ? 'work/' : ''}project` : `${home}/project`;
  const holder = `${home}/holder`;
  const allowed = `${holder}/allowed`;
  const target = hops === 0 ? `${home}/${builtin}` :
    targetKind === 'project' ? project : nestedProject ? `${home}/.codex/aws` : `${home}/secret`;
  const queries = [file(`${project}/source`), file(`${project}/nested/private`),
    file(`${holder}/private`), file(`${allowed}/source`), file(`${home}/ordinary`),
    file(`${target}/allowed.txt`), file(`${target}/known_hosts`), file(`${target}/private`),
    file(`${target}/child/source`), file(`${home}/other/private`),
    file(`${home}/.gnupg/private`), file(`${home}/state`)];
  const preload = file(`${home}/.gnupg/lib/no-sandbox.js`);
  const command = file(`${home}/.gnupg/fixture-command`, true);
  file(`${home}/.gnupg/codex`, true);
  if (nestedProject) fs.mkdirSync(`${home}/.codex`, { recursive: true });
  else fs.symlinkSync(home, `${home}/.codex`);
  queries.push(preload, command);
  const spellings = hops === 0 ? [target] : [`${home}/${builtin}`,
    ...(hops >= 3 ? [`${home}/hop`] : []),
    ...(hops >= 2 ? [`${allowed}/link`] : []), target];
  for (let i = 0; i < spellings.length - 1; i++) fs.symlinkSync(spellings[i + 1], spellings[i]);
  // A second linked block stays nested inside a potential child restoration.
  const nested = `${target}/child/nested`;
  fs.symlinkSync(`${home}/other`, nested);
  fs.symlinkSync(nested, `${home}/${builtin === '.ssh' ? '.aws' : '.ssh'}`);
  const blocks = [
    { builtin: true, spellings },
    { builtin: true, spellings: [`${home}/${builtin === '.ssh' ? '.aws' : '.ssh'}`, nested, `${home}/other`] },
    { builtin: true, spellings: [`${home}/.gnupg`] },
    { builtin: false, spellings: [holder] },
  ];
  const customBlocks = [holder];
  if (nestedProject) {
    queries.push(file(`${target}/credentials`), file(`${home}/.codex/state`));
    if (targetKind.endsWith('-deep')) queries.push(file(`${target}/work/sibling`));
    customBlocks.push(`${project}/nested`);
    blocks.push({ builtin: false, spellings: [`${project}/nested`] });
  }
  file(`${home}/empty.yaml`);
  fs.writeFileSync(`${home}/empty.yaml`, '');
  // A copied launcher locates its real preload inside a built-in block.
  fs.copyFileSync(launcherSource, `${home}/.gnupg/scode`);
  fs.chmodSync(`${home}/.gnupg/scode`, 0o755);
  return { home, project, holder, allowed, target, queries, blocks, customBlocks,
    harnessRoot: nestedProject ? `${home}/.codex` : home, preload: [preload], command: [command] };
}

// Check evaluators independently of scode, including ancestor mounts that hide
// earlier child mounts, exact files, metadata-only grants, and write caps.
assert.equal(seatbelt(parseProfile('(allow default)(deny file-read* (subpath "/a"))(allow file-read-metadata (literal "/a/x"))'), '/a/x', 'read'), false);
assert.equal(seatbelt(parseProfile('(deny default)(allow file-read* (literal "/a/x"))'), '/a/xy', 'read'), false);
assert.equal(bubblewrap(parseMounts('bwrap --bind /a/x /a/x --tmpfs /a --'), '/a/x/file', 'read'), false);
assert.equal(bubblewrap(parseMounts('bwrap --tmpfs /a --ro-bind /a/x /a/x --'), '/a/x', 'write'), false);

let cases = 0;
let checks = 0;
const mismatches = [];
const tasks = [];
function dryRun(executable, args, env) {
  return new Promise((resolve, reject) => {
    const process = spawn(executable, args, { env });
    let stdout = '', stderr = '';
    process.stdout.on('data', data => { stdout += data; });
    process.stderr.on('data', data => { stderr += data; });
    const timer = setTimeout(() => process.kill('SIGTERM'), 30000);
    process.on('error', reject);
    process.on('close', status => {
      clearTimeout(timer);
      if (status === 0) resolve(stdout);
      else reject(Error(`dry-run exit ${status}: ${stderr || stdout}`));
    });
  });
}
function check(f, allows, strict, ro, useHome, label, harness = false, customRuntime = false) {
  for (const platform of ['darwin', 'linux']) {
    tasks.push(async () => {
    const policy = { ...f, allows, strict, ro, platform,
      project: useHome ? f.home : f.project, harness: strict && harness ? [f.harnessRoot] : [],
      command: [harness ? `${f.home}/.gnupg/codex` : f.command[0]] };
    if (customRuntime) policy.blocks = [...f.blocks, { builtin: false, spellings: [`${f.home}/.gnupg`] }];
    const args = ['--dry-run', '--no-net', ...(strict ? ['--strict'] : []), ro ? '--ro' : '--rw',
      '-C', policy.project, ...f.customBlocks.flatMap(p => ['--block', p]),
      ...(customRuntime ? ['--block', `${f.home}/.gnupg`] : []),
      ...allows.flatMap(p => ['--allow', p]), '--', policy.command[0]];
    const env = { ...process.env, HOME: f.home, SCODE_CONFIG: `${f.home}/empty.yaml`, _SCODE_PLATFORM: platform };
    for (const key of ['SCODE_FS_MODE', 'SCODE_NET', 'SCODE_ACCOUNT_FILE', 'SCODE_ACCOUNT_ID', 'NODE_OPTIONS', 'CODEX_HOME']) delete env[key];
    const output = await dryRun(`${f.home}/.gnupg/scode`, args, env);
    const emitted = platform === 'darwin' ? parseProfile(output) : parseMounts(output);
    const evaluate = platform === 'darwin' ? seatbelt : bubblewrap;
    for (const query of [...new Set([...f.queries, ...policy.command])]) {
      for (const operation of ['read', 'write']) {
        const expected = permits(policy, query, operation);
        const actual = evaluate(emitted, query, operation);
        checks++;
        if (expected !== actual) mismatches.push({ label, platform, strict, ro, useHome,
          allows: allows.map(p => p.slice(f.home.length)), query: query.slice(f.home.length), operation, expected, actual });
      }
    }
    cases++;
    });
  }
}

if (selection === 'matrix' || selection === 'custom-links') {
  const f = fixture(0, 'custom-links');
  const writtenParent = `${f.home}/written`;
  const middleParent = `${f.home}/middle`;
  const target = `${f.home}/custom-target`;
  fs.mkdirSync(writtenParent);
  fs.mkdirSync(middleParent);
  f.queries.push(file(`${target}/private`), file(`${target}/child/source`));
  const spellings = [`${writtenParent}/link`, `${middleParent}/link`, target];
  fs.symlinkSync(target, spellings[1]);
  fs.symlinkSync(spellings[1], spellings[0]);
  f.blocks.push({ builtin: false, spellings });
  f.customBlocks.push(spellings[0]);
  for (const allows of [[writtenParent], [middleParent], [writtenParent, `${target}/child`], [target], [f.home]]) {
    for (const strict of [false, true]) for (const ro of [false, true]) {
      check(f, allows, strict, ro, false, `custom-links,allows=${allows.join(',')}`, true);
    }
  }
}

if (selection === 'matrix') {
  for (const hops of [0, 1, 2, 3]) {
    for (const targetKind of ['secret', 'project', 'nested-project']) {
      const f = fixture(hops, targetKind);
      const allowSets = [[], [f.allowed], [f.allowed, `${f.target}/allowed.txt`],
        [f.allowed, `${f.target}/child`], [f.target], [f.home],
        [`${f.home}/${hops === 0 ? '.aws' : 'holder'}`],
        [`${f.target}/allowed.txt`, f.allowed]];
      for (let a = 0; a < allowSets.length; a++) {
        // Cover both strict values for each topology/allow choice. Alternate
        // ro independently across choices; the reviewer cases use all four.
        for (const strict of [false, true]) {
          const ro = (a + hops + Number(strict)) % 2 === 0;
          check(f, allowSets[a], strict, ro, a === 5 || a === 6, `hops=${hops},target=${targetKind},allows=${a}`, a % 2 === 0, a === 7);
        }
      }
    }
  }
} else if (selection === 'nested-project') {
  for (const kind of ['nested-project', 'nested-project-deep']) {
    const f = fixture(1, kind);
    const allowSets = [[], [`${f.target}/allowed.txt`]];
    if (kind.endsWith('-deep')) allowSets.push([`${f.target}/work`]);
    for (const allows of allowSets) {
      for (const strict of [false, true]) for (const ro of [false, true]) {
        check(f, allows, strict, ro, false, `${kind},allows=${allows.join(',')}`, true);
      }
    }
  }
} else if (selection === 'runtime-grants') {
  const f = fixture(0, 'secret');
  for (const allows of [[f.home], [...f.preload, ...f.command]]) {
    for (const strict of [false, true]) for (const ro of [false, true]) {
      check(f, allows, strict, ro, false, `runtime-grants=${allows.length}`);
    }
  }
} else if (selection !== 'custom-links') {
  const f = fixture(2, 'secret', selection === 'ssh' ? '.ssh' : '.aws');
  for (const strict of [false, true]) for (const ro of [false, true]) {
    check(f, [f.allowed, `${f.target}/${selection === 'ssh' ? 'known_hosts' : 'allowed.txt'}`],
      strict, ro, false, `reviewer-${selection}`);
  }
}
async function main() {
  // Bounded concurrency; each task is a dry-run, never a sandbox or harness.
  let next = 0;
  await Promise.all(Array.from({ length: 4 }, async () => {
    while (next < tasks.length) await tasks[next++]();
  }));
  mismatches.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
  for (const mismatch of mismatches) console.log(JSON.stringify(mismatch));
  console.log(`policy model: ${cases} backend cases; ${checks} read/write checks; ${mismatches.length} mismatches`);
  process.exitCode = mismatches.length ? 1 : 0;
}
main().catch(error => { console.error(error); process.exitCode = 1; });
