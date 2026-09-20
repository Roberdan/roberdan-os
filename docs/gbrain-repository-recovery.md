# Conservative repository recovery

`bin/gbrain-repo-audit.py` records local and GitHub coverage in a private JSON
manifest. `bin/gbrain-recover-repos.py` consumes that manifest. Both tools keep
operational inventories, checkout paths and command output outside this repository.

The recovery command defaults to a plan. `--apply` requires a restore-tested
backup state plus matching archive checksums, and local `ollama:bge-m3` embeddings
at 1024 dimensions. It does not upgrade gbrain or invoke paid synthesis.

The CLI now processes only existing direct-child repositories of `~/GitHub`
(`--active-root` can name a different explicit root). `WareHouse`, `ParkingLot`,
worktree containers, symlinks, removed repositories and remote-only entries are
excluded even when an old manifest lists them. Scope is rechecked before each
command; moving a repository out of the active folder blocks further processing.
Excluded historical records are retained, not deleted or counted as current work.
Current local Git metadata is discovered afresh, including top-level linked
worktrees: a saved manifest is never used to resurrect removed projects or omit
new active ones. The legacy `--manifest` argument remains for command compatibility.
Every resumed pass rechecks previously verified projects against current local HEAD.
Owned clean snapshots advance only by fast-forward from the active local repository;
divergence, ignored/untracked files or a moving local HEAD block verification rather
than resetting a branch or reporting an old snapshot as current.
Renames remain blocked unless `--rename-proof` supplies evidence from the exact
sync performed on an isolated restored database: same source metadata, snapshot,
rename batch and clean installed gbrain revision, all active page IDs retained,
indexed revision reached, production metadata unchanged. The evidence cannot
authorize deletions, reconciliation or a different rename batch. Live retention
and revision checks still run after the operation.

```sh
python3 bin/gbrain-recover-repos.py \
  --manifest /private/path/repo-coverage.json \
  --backup /private/path/backup/state.json \
  --state-dir /private/path/recovery \
  --blocked-source source-without-access
```

Add `--apply` only after reviewing the plan and confirming its authorization.
Use repeated `--blocked-source` arguments for sources this execution must not
access. A denied existing source is recorded as blocked rather than accessed
through another transport.

## Guarantees and boundaries

- Original checkouts, intentional bare containers and linked worktrees are not
  edited. Git content is copied into managed checkouts with hooks disabled.
- Every managed checkout has an ownership marker. Unknown existing directories
  and modified snapshots are not overwritten.
- Existing indexes requiring full reconciliation, deletion, rename or
  un-syncable-page deletion are blocked before actual synchronization.
- Synchronization uses the automatic code/document strategy without pull or
  automatic embedding. Retained page identities and the stored index revision
  must match the validated snapshot.
- Vector catch-up uses `embed --stale --source`, not `dream --phase embed`.
  In gbrain 0.50 the latter is global even when a source argument is supplied.
  The final dry-run must report zero eligible stale chunks, including stale
  content/signatures rather than only missing vectors.
- Missing anchors, inaccessible remotes, empty repositories, changed local
  heads and stalled embeddings remain explicit blocked records. No successful
  exit is returned while a recorded repository is blocked.
- Resume uses the same state directory. Verified entries belong to this
  one-time recovery snapshot, not an assertion that future commits are indexed.
  This runner does not replace a scheduled incremental refresh service.

Full command evidence and per-repository state are written atomically under the
private state directory. The backup is retained. A reviewer PASS validates the
implementation, not live coverage or the task's final completion gate.
