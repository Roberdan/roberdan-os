# Security Policy

roberdan-os is a personal agentic operating system maintained by one person, published
so others can learn from its structure. There is no company behind it, no SLA and no
bug bounty. Reports are still very welcome and are handled seriously and promptly —
just on a best-effort basis.

## Supported versions

Only the latest release on `main` (see `VERSION`). Older tags are not patched.

## Reporting a vulnerability

**Report privately. Do not open a public issue for a security problem.**

1. **Preferred:** GitHub private vulnerability reporting —
   [open a draft advisory](https://github.com/Roberdan/roberdan-os/security/advisories/new).
   It is enabled on this repository.
2. **Fallback:** email `roberdan@fightthestroke.org` with `[roberdan-os security]` in
   the subject.

Please include: what you found, how to reproduce it, and what an attacker gets out of
it. A proof-of-concept helps. Acknowledgement within a few days; a fix or an explicit
"won't fix, here's why" as soon as the problem is understood.

Please **do not** include real confidential data in a report — describe the shape of
the leak, not its content.

## In scope

- **Privacy-boundary failures.** Anything that gets local-only content into a
  committable or publishable artefact: the confidential dossier (`private/`), kanban
  card content (`kanban/todo|doing|done/`), or vault material. This includes bypasses
  of `test/leak-check.sh` and of the `pre-commit` hook that runs it.
- **Code execution paths.** `hooks/`, `bin/`, `test/`, `factory/`, `kanban/kb.sh` —
  command injection, unsafe `eval`, path traversal, unquoted expansion reachable from
  attacker-influenced input (a filename, a card title, a fetched changelog).
- **Agent supply chain.** A skill, generated wrapper, or MCP configuration in this
  repo that could be used for prompt injection with real consequences — for example
  steering an agent into reading `private/` and writing it somewhere committable.
- **Self-modification guardrails.** Anything that lets the meta-loop (`learn/`,
  `evolve/`, `ontology/`) write to `behavior/`, `rules/`, `agents/` or `AGENTS.md`
  without the human gate, or auto-commit where it must only propose.
- **Secret handling.** Credentials or tokens committed, logged, or exposed by any
  script here.

## Out of scope

- **An agent giving bad, wrong or unsafe advice.** That is a quality problem, not a
  vulnerability — open a normal issue. The system is explicitly advisory and its
  irreversible actions sit behind human gates (`AGENTS.md` § Human gates).
- **Third-party tools.** Claude Code, GitHub Copilot, Codex, gstack, gbrain, Ollama,
  Obsidian — report those upstream. Only their *wiring inside this repo* is in scope.
- **The salted denylist tradeoff.** `test/denylist.sha256` uses a committed salt: it
  stops casual reading and keeps CI logs clean, but a dictionary attack against
  guessed terms is possible by design. This is documented in
  `docs/privacy-leak-check.md` and accepted, not a finding.
- **Anything requiring an attacker who already has local shell access** to the
  maintainer's machine. At that point the dossier is readable directly.

## Known and accepted risk: this repository runs code

By design, this system installs git hooks, shell scripts and agent skills that
**execute on your machine**. Running a fork means running that fork's code. Read
`hooks/`, `bin/` and any third-party skill before installing — the canon's own rule
(`rules/best-practices.md` § Agent supply chain) is to review every skill and MCP
server on first use *and on every update*, and it applies to this repository too.
