# evolve-protocol — watcher settimanale dei tool (draft-only)

Tiene roberdan-os aggiornato sulle novità di Claude Code / GitHub Copilot / Codex,
**proponendo** patch — mai applicandole al comportamento. Vedi [[ADR-0001]].

## Cadenza

launchd `com.roberdan.rda-evolve`, **settimanale**. Scatta a prescindere dal tool aperto.

## Flusso

`evolve/watch.sh`:
1. **Fetch** changelog/release note delle fonti (URL versionati) → confronta con l'ultima
   versione vista (stato durevole `~/.roberdan-os/evolve/seen.json`).
2. **Diff capability:** per ogni novità, valuta se tocca qualcosa che roberdan-os usa
   (hook, skill, agent, scheduling, MCP, memoria).
3. **Proponi** in `roberdan-os/proposals/<YYYY-MM-DD>-<slug>.md`: cosa cambia, perché,
   patch suggerita, **citazione fonte (URL + versione + data)**. Niente citazione → niente proposta.

## Invarianti (hard)

- **Mai** auto-commit su `behavior/ rules/ agents/ AGENTS.md` — solo draft in `proposals/`.
- Enforcement meccanico: `hooks/post-task-sync.sh` auto-committa **solo** `platforms/` (git add scoped, opt-in). `test/validate.sh` fa drift-check.
- No-hallucination: ogni claim ha una fonte verificabile.

## Done

Una proposta è "pronta" quando Roberto la rivede e la promuove a PR/commit. Il watcher
non chiude mai il cerchio da solo sul canone.
