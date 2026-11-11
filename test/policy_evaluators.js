'use strict';

const { under } = require('./policy_model');

// Parse S-expressions rather than searching for text positions. Metadata and
// execution grants do not grant file contents. Unknown file predicates fail.
function parseProfile(text) {
  const tokens = text.replace(/^\s*[;#].*$/gm, '').match(/#?"(?:\\.|[^"\\])*"|[()]|[^\s()]+/g) || [];
  let index = 0;
  function parse() {
    const token = tokens[index++];
    if (token !== '(') return token;
    const expression = [];
    while (tokens[index] !== ')') {
      if (index === tokens.length) throw Error('Unterminated SBPL expression');
      expression.push(parse());
    }
    index++;
    return expression;
  }
  const rules = [];
  while (index < tokens.length) rules.push(parse());
  return rules.filter(Array.isArray);
}

function predicateMatches(predicate, query) {
  const [kind, ...args] = predicate;
  if (kind === 'subpath') return under(query, JSON.parse(args[0]));
  if (kind === 'literal') return query === JSON.parse(args[0]);
  if (kind === 'require-all') return args.every(p => predicateMatches(p, query));
  if (kind === 'require-any') return args.some(p => predicateMatches(p, query));
  if (kind === 'require-not') return !predicateMatches(args[0], query);
  throw Error(`Unsupported file predicate: ${kind}`);
}

function seatbelt(rules, query, operation) {
  let allowed = false;
  for (const [effect, ...body] of rules) {
    if (!['allow', 'deny'].includes(effect)) continue;
    const operations = body.filter(item => typeof item === 'string');
    if (!operations.some(op => ['default', 'file*', `file-${operation}*`,
      operation === 'read' ? 'file-read-data' : 'file-write-data'].includes(op))) continue;
    const predicates = body.filter(Array.isArray);
    if (!predicates.length || predicates.some(p => predicateMatches(p, query))) allowed = effect === 'allow';
  }
  return allowed;
}

// Fixture paths contain no shell metacharacters. Fail instead of silently
// interpreting an escaped argv incorrectly if that invariant changes.
function parseMounts(text) {
  const line = text.split('\n').find(value => value.startsWith('bwrap '));
  if (!line || /[\\'"]/.test(line)) throw Error('Unexpected dry-run bwrap rendering');
  const words = line.split(/\s+/);
  const mounts = [];
  for (let i = 0; i < words.length; i++) {
    const flag = words[i];
    if (['--bind', '--ro-bind', '--dev-bind'].includes(flag)) {
      mounts.push({ source: words[++i], target: words[++i], ro: flag === '--ro-bind' });
    } else if (['--tmpfs', '--proc', '--dev'].includes(flag)) {
      mounts.push({ source: null, target: words[++i], ro: false });
    } else if (flag === '--') break;
  }
  return mounts;
}

function bubblewrap(mounts, query, operation) {
  let allowed = false;
  for (const mount of mounts) {
    if (!under(query, mount.target)) continue;
    // Queries name existing fixture host files, not newly created tmpfs files.
    // A null-device bind hides the host file even though the replacement opens.
    allowed = mount.source !== null && mount.source !== '/dev/null' &&
      (operation === 'read' || !mount.ro);
  }
  return allowed;
}

module.exports = { parseProfile, seatbelt, parseMounts, bubblewrap };
