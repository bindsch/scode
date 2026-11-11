'use strict';

const assert = require('node:assert/strict');
const { permits } = require('./policy_model');
const { parseProfile, seatbelt, parseMounts, bubblewrap } = require('./policy_evaluators');

const policy = {
  home: '/home', project: '/home/project', strict: true, ro: false, platform: 'darwin',
  blocks: [
    { builtin: true, spellings: ['/home/.aws', '/home/holder/allowed/link', '/home/secret'] },
    { builtin: true, spellings: ['/home/.ssh', '/home/secret/child/nested', '/home/other'] },
    { builtin: false, spellings: ['/home/holder'] },
  ],
  allows: ['/home/holder/allowed', '/home/secret/child'], harness: [], preload: [], command: [],
};
for (const platform of ['darwin', 'linux']) {
  const p = { ...policy, platform };
  assert.equal(permits(p, '/home/secret/child/file', 'read'), true);
  assert.equal(permits({ ...p, harness: ['/home'] }, '/home/other/private', 'read'), false);
  assert.equal(permits(p, '/home/secret/private', 'read'), false);
  assert.equal(permits({ ...p, harness: ['/home'] }, '/home/secret/private', 'write'), false);
  assert.equal(permits({ ...p, project: '/home/secret/child', allows: [] }, '/home/secret/child/file', 'write'), true);
  assert.equal(permits({ ...p, project: '/home/secret/child', allows: [], ro: true }, '/home/secret/child/file', 'write'), false);
  assert.equal(permits({ ...p, command: ['/home/secret/private'] }, '/home/secret/private', 'read'), true);
  assert.equal(permits({ ...p, command: ['/home/secret/private'] }, '/home/secret/private', 'write'), false);
  assert.equal(permits({ ...p, command: ['/home/holder/private'] }, '/home/holder/private', 'read'), false);
  assert.equal(permits(p, '/home/ordinary', 'read'), false);
  assert.equal(permits({ ...p, strict: false }, '/home/ordinary', 'write'), true);
  assert.equal(permits({ ...p, system: ['/system'] }, '/system/file', 'read'), true);
  assert.equal(permits({ ...p, system: ['/system'] }, '/system/file', 'write'), false);
  const nested = { ...p, project: '/home/.codex/aws/project', harness: ['/home/.codex'], allows: [],
    blocks: [{ builtin: true, spellings: ['/home/.aws', '/home/.codex/aws'] }] };
  assert.equal(permits(nested, '/home/.codex/aws/credentials', 'read'), false);
  assert.equal(permits(nested, '/home/.codex/aws/credentials', 'write'), false);
  assert.equal(permits(nested, '/home/.codex/aws/project/source', 'read'), true);
  assert.equal(permits(nested, '/home/.codex/aws/project/source', 'write'), true);
}
// Synthetic policies make ordering errors visible without depending on scode.
const rules = parseProfile('(allow default)(deny file-read* file-write* (subpath "/home/secret"))' +
  '(allow file-read* file-write* (subpath "/home/secret/child"))' +
  '(deny file-read* file-write* (subpath "/home/secret/child/nested"))' +
  '(deny file-write* (subpath "/home/secret/child"))');
assert.equal(seatbelt(rules, '/home/secret/child/file', 'read'), true);
assert.equal(seatbelt(rules, '/home/secret/child/file', 'write'), false);
assert.equal(seatbelt(rules, '/home/secret/child/nested/private', 'read'), false);
assert.equal(seatbelt([...rules, ...parseProfile('(deny file-read* (subpath "/home/secret"))')],
  '/home/secret/child/file', 'read'), false);
const bounded = parseProfile('(allow default)(deny file-read* (require-all ' +
  '(subpath "/home/secret") (require-not (subpath "/home/secret/child"))))');
assert.equal(seatbelt(bounded, '/home/secret/child/file', 'read'), true);
assert.equal(seatbelt(bounded, '/home/secret/private', 'read'), false);
const mounts = parseMounts('bwrap --bind /home /home --tmpfs /home/secret ' +
  '--ro-bind /home/secret/child /home/secret/child --tmpfs /home/secret/child/nested --');
assert.equal(bubblewrap(mounts, '/home/secret/child/file', 'read'), true);
assert.equal(bubblewrap(mounts, '/home/secret/child/file', 'write'), false);
assert.equal(bubblewrap(mounts, '/home/secret/child/nested/private', 'read'), false);
console.log('policy oracle and evaluator known answers: passed');
