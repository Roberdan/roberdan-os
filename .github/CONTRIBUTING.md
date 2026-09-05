# Contributing to roberdan-os

Thanks for helping make AI-assisted work more reliable and easier to understand.
This is a working configuration you can inspect, improve, and fork, not a promise that
instructions alone make agents safe or correct.

## Useful places to start

- Reproduce a Copilot CLI integration problem with a minimal example.
- Improve a regression test for generation, installation, or model selection.
- Clarify an onboarding step that did not work on your machine.
- Compare models on the same real task, reporting limitations as well as results.
- Preserve Claude Code and Codex compatibility while improving the Copilot-first experience.

Check [existing issues](https://github.com/Roberdan/roberdan-os/issues) before opening a new
one. For changes spanning several components, discuss the intended outcome first.
Please do not turn an unrelated finding into extra scope in an existing pull request.

## Work locally without changing your agent setup

Prerequisites: Git, Bash, Python 3, and `jq`. Install `shellcheck` for the same shell linting
used by CI. These steps do not require model credentials or invoke a paid model.

```bash
git clone https://github.com/Roberdan/roberdan-os.git
cd roberdan-os
git switch -c fix/describe-your-change
bash bin/sync.sh --emit-only
bash test/test-copilot-adapter.sh
bash test/test-model-economy.sh
```

Run the smallest existing test covering your change while iterating. Before submitting,
run the CI entry point:

```bash
bash test/validate.sh
```

Some diagnostics depend on optional integrations installed on your machine. Report those
separately from regression failures; do not remove a check merely to make a local run pass.
Use a separate Git worktree when another agent or person is changing the same checkout.

## Where changes belong

| Change | Source to edit |
|---|---|
| Operating instructions | `AGENTS.md`, `behavior/`, or `rules/` |
| Specialist behavior | `agents/` |
| Reusable skill | `skills/<name>/skill.md` |
| Generated client integration | `bin/sync.sh` and its helpers |
| Copilot lifecycle integration | `hooks/copilot/` |
| Regressions | `test/` |
| Setup and operator instructions | `README.md` and `docs/USAGE.md` |

`platforms/` is generated and ignored by Git. Do not hand-edit or commit its contents.
The same applies to installed skill wrappers: change the canonical source, then regenerate.
Use `identity/` for your own fork's identity, not to replace the upstream operator profile.

## What to include in a pull request

Explain the problem, the observable change, the tests you ran, and any behavior you did not
exercise. Update the relevant guide and `CHANGELOG.md` when behavior changes.
Keep commits focused; avoid unrelated formatting or generated artifacts.

Model availability is not a benchmark. Include the exact model ID, client version, task,
reasoning/context settings, and measured usage when making a comparison. Do not infer prices
or capabilities from a model's name, and do not run paid comparisons on someone else's account
without permission.

Changes to operating rules, agent behavior, privacy controls, or release infrastructure need
maintainer review. Never bypass safeguards to get a contribution accepted.

## Keep private material out

Do not include credentials, personal task cards, private memory, customer information, or
raw session transcripts in issues, tests, or pull requests. Use synthetic examples with
`example.com` addresses. Stage named files deliberately rather than using `git add -A`.
Run the repository's privacy checks before publishing.

Contributions are distributed under the repository's [MIT license](../LICENSE).
