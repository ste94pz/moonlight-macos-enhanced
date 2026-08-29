# Git workflow

## Branch model

The configured remotes are `upstream` for `skyhua0224/moonlight-macos-enhanced` and `origin` for `ste94pz/moonlight-macos-enhanced`. Verify them with `git remote -v`; never infer direction from a branch name alone.

- `upstream/master` is the external reference.
- `master` is the fork base, kept as close as practical to upstream plus internal general documentation.
- `feature/*` and `fix/*` contain independent functional changes and their authoritative branch-specific documentation.
- `release/complete` integrates selected feature/fix branches with explicit merge commits, normally `git merge --no-ff`, and may contain complete-release packaging/build changes. New features are not normally developed there.
- `pr/*` branches are temporary, start directly from the appropriate upstream branch, and contain only commits intended for upstream.

Always begin with:

```bash
git status --short --branch
git remote -v
```

Do not switch with uncommitted work. Use `git merge-base`, `git log` and `git diff` to establish ancestry and real deltas before integrating.

## Update `master` from upstream

Fetch without rewriting existing branches, inspect the delta, then fast-forward when possible:

```bash
git fetch upstream --prune
git switch master
git status --short --branch
git log --oneline --left-right master...upstream/master
git merge --ff-only upstream/master
```

If internal documentation makes a fast-forward impossible, stop and inspect the graph. Choose an explicit merge or a deliberate documentation replay according to project policy; do not silently rebase published fork branches. Push only when separately requested.

## Update a feature or fix branch

Start new independent work from the current fork base:

```bash
git switch master
git switch -c feature/<name>
```

For an existing branch, first inspect its base and incoming master changes:

```bash
git switch feature/<name>
git status --short --branch
git merge-base master HEAD
git log --oneline --left-right HEAD...master
git merge --no-ff master
```

Use a merge for already shared branches unless a history rewrite was explicitly agreed. A correction that logically belongs to a feature must be committed on that feature branch, then reintegrated into `release/complete`; do not leave the only fix on the integration branch.

Maintain feature-specific documentation beside the implementation and update it in a separate `docs:` commit when behavior or invariants change.

## Integrate the complete release

Verify the source branch, its diff from `master`, and the release working tree before merging:

```bash
git switch release/complete
git status --short --branch
git merge-base master feature/<name>
git diff --stat master...feature/<name>
git merge --no-ff feature/<name>
```

Repeat independently for each selected feature/fix. `release/complete` receives feature documentation naturally through these merges. Do not add a merge solely to propagate a later documentation commit without an explicit decision.

Changes made directly on `release/complete` should be limited to integration, packaging or complete-build logic. Record integration-specific behavior in `docs/development/branches/release-complete.md`, linking to feature documents instead of copying them. Run the normal build plus cross-feature manual checks before release.

## Prepare an upstream PR

Create the PR branch from the upstream baseline, not from a fork feature branch:

```bash
git fetch upstream --prune
git switch -c pr/<topic> upstream/master
```

Identify functional commits from the source branch and inspect each one:

```bash
git log --oneline upstream/master..feature/<name>
git show --stat <commit>
git cherry-pick <functional-commit> [<functional-commit> ...]
```

Exclude `docs:` commits containing `AGENTS.md`, `docs/development/` or other internal fork documentation. If a feature commit mixes internal docs with code, split/recreate it rather than importing the internal files. Verify the result before any push:

```bash
git diff --stat upstream/master...HEAD
git log --oneline upstream/master..HEAD
```

An upstream-facing code comment or public user document may be included only when it is genuinely part of the contribution; the default exclusion applies to internal development guidance.

## Commit discipline

- Functional and internal-documentation changes use separate Conventional Commits (`feat:`, `fix:`, `build:`, then `docs:`).
- Do not mix unrelated feature/fix branches.
- Do not develop ordinary feature behavior directly on `release/complete`.
- Do not push, merge, rebase or cherry-pick merely as a side effect of documentation work.
- Before handoff, verify cited paths, compare documentation with the branch diff, and leave `git status` clean on every modified branch.
