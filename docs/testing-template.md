# Testing template for a repo — budget, place, shape

The reusable shape every repo adopts to implement
[`rules/best-practices.md` § Tests](../rules/best-practices.md#tests-budget-place-shape-roberto-2026-10-11)
(decided by Roberto on 2026-10-11, [ADR-0006](adr/0006-test-budget.md)). The rule says *what*;
this file says *how*, per layer and per stack. A repo adopts it in its own PR, with its own
`.test-critical` and `.test-budget`.

**Until a repo has adopted it, nothing changes for that repo:** with no `.test-critical` file, or
with no nightly actually running, the whole repo counts as critical and the full suite runs before
every merge, exactly as before.

## 1. Four layers, each with a time budget

| Layer | What it runs | Budget |
|---|---|---|
| pre-commit | formatter + linter on staged files, secret/privacy scan. **No tests** | ≤ 10 s |
| pre-push | typecheck/compile + RELATED tests; full suite only if the **escape list** is touched (lockfile, test config, DB migrations/schema, shared harness/fixtures) | ≤ 90 s |
| PR CI | typecheck, lint, build, related tests; full parallel suite only if a `.test-critical` glob matches the diff | ≤ 10 min |
| nightly CI (scheduled) + `test:full` on request | full suite, parallel/sharded, `.test-budget` ratchet, weekly mutation run on critical paths | ≤ 15 min |

Changes are **batched**: related fixes travel in one PR so the full-suite cost (when due) is paid
once. A layer over budget is a bug of the test system — open a finding/card and fix it; never skip
the layer.

## 2. Two files every adopting repo keeps

**`.test-critical`** — one glob per line, then ` # ` and a one-line reason. Touching one ⇒ full
suite before merge + thor gate 8b (mutation). Changing this file is itself critical. Start broad
(whole money/rules/DB/approval packages), narrow later with a reason.

```
packages/engine/**      # money engine: every euro flows through here
packages/db/**          # schema and migrations
.test-critical          # changing the list is critical
```

**`.test-budget`** — the last recorded full-suite figures, written by the nightly job:

```
wall_seconds=150
test_files=471
recorded=2026-10-11 sha=<last green full run>
```

## 3. Per stack

| Stack | Related tests (pre-push) | Full suite / parallelism | Weekly mutation (critical paths only) |
|---|---|---|---|
| TS / vitest | `vitest related <changed files> --run` (MirrorBuddy `scripts/smart-test.sh` is a working in-house example, with the escape hatch to the full suite) | `fileParallelism: true`; one DB per file cloned from a migrated template; CI `--shard` + `--merge-reports` | Stryker |
| Python | `pytest-testmon` or a path→test map | `pytest-xdist -n auto` (or the repo's own sharder) | `mutmut` |
| Rust | `cargo nextest run -p <changed crates>` | `cargo nextest` | `cargo-mutants --in-diff` |
| Swift | `swift test --parallel --filter <changed module>` | nightly full suite | — |
| Bash (roberdan-os) | `test-*.sh` whose name matches the changed files | `test/validate.sh` in CI | mutant probes already in `test/` |

## 4. Where the night runs

- **GitHub scheduled workflow (preferred)** for everything on synthetic data: it does not depend
  on the Mac being awake. A DB-backed suite needs a service container (e.g. Postgres).
- **Local launchd** only for what cannot leave the Mac (golden tests on real data, private Swift
  repos where macOS runners cost ~10× Linux minutes). Conditions: on AC power (`pmset -g batt`
  says "AC Power") and no suite already running. **Catch-up rule:** at every wake/login, if the
  last green full run is older than 24 h and on AC, run now. The result goes to a file the
  morning check reads.

## 5. Red night — the procedure

1. **Who sees it:** the job opens a kanban card + a bus message; Roberto's morning recap shows one
   line: "notte rossa: <repo>, <n> test, colpevole probabile <PR>".
2. **Culprit:** the job stores the last green SHA; on red it runs `git bisect run` over
   last-green..HEAD with only the failing files — minutes, not hours. The card names the merge.
3. **What is blocked meanwhile:** merges touching `.test-critical` are blocked until green. Other
   merges continue. Red for more than 48 h ⇒ every merge blocks except the fix.
4. **Fix:** revert the culprit or fix forward, then `test:full` on request.

## 6. Monthly pruning

Once a month (never on `.test-critical` paths): delete or merge tests that kill no unique mutant,
duplicate another test's assertions, or test a deleted feature. "Never failed" alone is not a
reason. Fold round-named files (`audit3-*`, `round12`, `-2`) into the behaviour file they test.

## 7. Anti-regrowth checks (mechanical, not prose)

Each repo wires these through **its own hook runner** (lefthook, husky, plain `.git/hooks`) and
its own CI. They are deliberately **not** added to roberdan-os's shared guest hook
(`bin/install-git-hooks.sh --into <repo>`): that hook is a shim that goes live in every repo where
it is installed as soon as roberdan-os `main` is pulled, which would migrate repos by side effect.

| # | Check | Where | Fails when |
|---|---|---|---|
| 1 | `.test-budget` ratchet | nightly + PR CI | full-suite wall time **or** test-file count exceeds the record by more than 10% and the PR body has no `Test-budget: <why>` line. The record is lowered automatically when the suite gets faster or smaller |
| 2 | Test-name lint | pre-commit | a NEW test file matches `(audit\|round\|pass\|wave)[0-9]\|-[2-9]\.\|regression-plan\|fix-` — names must say the behaviour |
| 3 | New-test-file counter | PR CI | a PR adds more than 2 test files with no new source module (warning, asks thor for the why); more than 5 fails |
| 4 | Hook timer | pre-commit / pre-push | prints its wall time; over budget twice in a row opens a card |
| 5 | Wiring check in roberdan-os | `test/validate.sh` | an **adopted** repo lacks `.test-critical` or `.test-budget`. Not wired yet: it would be red on day one, before any repo migrates. It is added once the first repo has adopted the template |

Sketch of check 2 for a shell hook (adapt the glob to the repo's test naming):

```bash
git diff --cached --name-only --diff-filter=A \
  | grep -E '(\.test\.|_test\.|/test_|test-)' \
  | grep -E '(audit|round|pass|wave)[0-9]|-[2-9]\.|regression-plan|fix-' \
  && { echo "test file named after a round, not a behaviour"; exit 1; } || true
```

## 8. Adoption checklist (one PR per repo)

1. Add `.test-critical` (broad) and `.test-budget` (measured with one full run).
2. pre-commit: drop any test run; add the test-name lint.
3. pre-push: typecheck + related tests + escape list; print wall time.
4. PR CI: related tests always; full suite only when `.test-critical` matches.
5. Nightly workflow (or launchd for Mac-only suites) with ratchet, bisect on red, card + bus message.
6. Fold round-named test files into their behaviour files.
7. Repo `AGENTS.md`: one line pointing here, plus any repo-specific escape-list entries.
