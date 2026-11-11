'use strict';

// Independent, declarative oracle for docs/policy.md. Inputs are absolute,
// normalized paths; each block supplies its written/intermediate/target names.
// Allows have already passed source-authority validation (CLI in the fixture).
// This function does no I/O and never examines a generated rule or mount.
const under = (path, parent) => path === parent || path.startsWith(`${parent.replace(/\/$/, '')}/`);
const child = (path, parent) => path !== parent && under(path, parent);

function retainedBlocks(policy) {
  return policy.blocks.filter(block => !policy.allows.some(allow =>
    under(block.spellings[0], allow) || under(block.spellings.at(-1), allow)));
}

function permits(policy, query, operation) {
  const { project, home, allows, harness, strict, ro, platform } = policy;
  const blocks = retainedBlocks(policy);
  const names = block => platform === 'linux' ? [block.spellings.at(-1)] : block.spellings;
  const inProject = under(query, project);
  const systemRead = operation === 'read' && (policy.system || []).some(path => under(query, path));
  const exposed = (!strict && (platform === 'darwin' || under(query, home))) || systemRead || inProject ||
    allows.some(path => under(query, path)) || harness.some(path => under(query, path));
  const deniedBy = block => {
    const roots = names(block);
    if (!roots.some(path => under(query, path))) return false;
    if (block.builtin && inProject && roots.some(path => under(project, path))) return false;
    return !allows.some(allow => under(query, allow) && roots.some(path => child(allow, path)));
  };
  const blocked = blocks.some(deniedBy);
  // Runtime files cannot bypass a retained custom block, even a child allow.
  const runtime = [...policy.preload, ...policy.command].includes(query) &&
    !blocks.some(block => !block.builtin && names(block).some(path => under(query, path)));
  if (operation === 'write' && ro && inProject) return false;
  return (exposed && !blocked) || (operation === 'read' && runtime);
}

module.exports = { permits, retainedBlocks, under, child };
