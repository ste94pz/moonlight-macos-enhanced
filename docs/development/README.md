# Fork development documentation

This fork maintains macOS-specific streaming, rendering, audio, input, diagnostics and host-integration enhancements on top of `skyhua0224/moonlight-macos-enhanced`. Git currently names the fork remote `origin` (`ste94pz/moonlight-macos-enhanced`) and the source repository `upstream` (`skyhua0224/moonlight-macos-enhanced`). The remote URLs, rather than assumptions about GitHub fork metadata, are the source of truth.

## Branch roles

- `upstream/master`: external baseline used to synchronize the fork.
- `master`: fork baseline, kept close to upstream and containing general internal documentation. At the time this documentation was introduced it matched `upstream/master` before the documentation commit.
- `feature/*`: one independently maintainable functional change. Its detailed documentation lives with it under `docs/development/branches/`.
- `fix/*`: one independently maintainable correction, following the same isolation rule as feature branches.
- `release/complete`: integration branch for the complete distributable, explicit feature/fix merges, and release-only build or packaging work.
- `pr/*`: temporary clean branches based directly on the appropriate upstream branch; only upstream-bound commits belong here.

See [WORKFLOW.md](WORKFLOW.md) for commands and update procedures.

## Document index

- Repository operating rules: [`AGENTS.md`](../../AGENTS.md)
- Code navigation and component boundaries: [ARCHITECTURE.md](ARCHITECTURE.md)
- Git/upstream workflow: [WORKFLOW.md](WORKFLOW.md)
- Feature and release details: `docs/development/branches/` on the branch implementing or integrating that work

## Maintained customizations

The branch list, not this page, determines what is currently shipped. The presently maintained branch-specific work is:

- `feature/dualshock-motion-touchpad`: DualShock 4 motion and touchpad input; authoritative document `branches/dualshock-motion-touchpad.md` on that branch.
- `fix/english-localization-coverage`: removal of hard-coded non-English UI text and completion of English fallback coverage; authoritative document `branches/english-localization-coverage.md` on that branch.
- `feature/italian-localization`: Italian language selection and resources layered on the English coverage branch; authoritative document `branches/italian-localization.md` on that branch.
- `fix/reconnect-lifecycle`: completion-aware, serialized teardown before reconnect; authoritative document `branches/reconnect-lifecycle.md` when that branch is checked out or integrated.
- `release/complete`: integration of the two feature branches above plus release-specific build logic; authoritative document `branches/release-complete.md` on that branch.

General architecture stays in [ARCHITECTURE.md](ARCHITECTURE.md); this index intentionally does not repeat feature internals.
