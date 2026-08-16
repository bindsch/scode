# Hooks

The audit itself lives in `code-review`, which owns the reviewers, the prompts,
and the verdict. Hookrun's job is only to decide when it runs and whether a
failure stops the commit.

`code-review run` follows the work: it reviews what changed, or the whole tree
when nothing has. It fires at `task-end`, the moment the writing agent finishes
a turn, because a finding is still cheap to act on then. Auditing at commit time
reports problems into code that has already been committed.

`code-review gate` reads the verdict the review recorded and calls no model, so
it refuses a commit without adding the review's latency to one.

The gate is discipline, not a boundary. Its verdict lives in `.code-review/`
inside the repository, which the writing agent can also write, so an agent
determined to bypass it can. It catches mistakes; it does not contain an
adversary.

Two timing limits follow from `async`. A turn that edits and commits without the
review finishing has no fresh verdict, and the gate refuses rather than guesses
— so a commit can be blocked waiting for a review that is still running. That is
the intended direction of failure, but it means "adds no latency" describes the
gate itself, not always the commit.

The task-end shim lives in `.claude/settings.json`. Commit it and a fresh clone
fires reviews once its owner approves the configuration; leave it untracked and
each clone installs its own. The commit gate is not:
Git hooks live in `.git/hooks`, which is never committed. Until it is installed,
reviews run and commits are not gated.

```sh
hookrun trust --allow-shell   # approve these commands after reading them
hookrun install claude git    # task-end shim, plus the pre-commit gate
```

Trust comes first: `install` refuses to write shims for a configuration nobody
has approved, so running it first leaves no gate at all. `install git` also
declines to replace a `pre-commit` hook it did not write, and says so while
still exiting successfully, so read its output rather than its exit status.

That approval is what stops this file from being a way around the sandbox.
Hookrun pins a digest of the approved configuration and refuses to run when it
no longer matches, so an agent editing the `run:` lines below cannot have them
executed -- the next fire reports the configuration as changed and asks for
review instead.

## Hook: review
- on: task-end
- mode: async
- timeout: 1800
- run: code-review run --profile default

## Hook: review-gate
- on: commit
- mode: blocking
- run: code-review gate
