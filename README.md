# roberdan-os

Fonte canonica unica del sistema agentico di Roberto D'Angelo. Una sola fonte
versionata da cui ogni tool (Claude Code, GitHub Copilot CLI+VS Code, Codex,
ChatGPT/Claude web) consuma lo stesso comportamento.

**Principio:** conoscenza centralizzata, esecuzione per-platform, comportamento
unificato. `AGENTS.md` è l'entry universale; i wrapper runtime sono generati da
`bin/sync.sh`, mai copiati a mano.

## Stato

Bootstrap (Fase 0). Il piano completo è in [`docs/plan.md`](docs/plan.md) — in
rifinitura su Ultraplan. L'implementazione (Fasi 1-6) parte dopo l'approvazione
del piano.

## Privacy

`private/` è gitignored: contiene il dossier Microsoft-confidenziale (clienti,
deal, persone) e non entra mai in git né in alcun bundle pubblico. Solo la
voce/stile non sensibile è committata.
