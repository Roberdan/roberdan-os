# roberdan-os

Fonte canonica unica del sistema agentico di Roberto D'Angelo. Una sola fonte
versionata da cui ogni tool (Claude Code, GitHub Copilot CLI+VS Code, Codex,
ChatGPT/Claude web) consuma lo stesso comportamento.

**Principio:** conoscenza centralizzata, esecuzione per-platform, comportamento
unificato. `AGENTS.md` è l'entry universale; i wrapper runtime sono generati da
`bin/sync.sh`, mai copiati a mano.

## Stato

Canone costruito (Fasi 0-5). `test/validate.sh` verde: frontmatter, link, drift,
shellcheck, leak-check. Piano completo in [`docs/plan.md`](docs/plan.md).

| Componente | Dove |
|---|---|
| Entry universale | [`AGENTS.md`](AGENTS.md) |
| Behavior | `behavior/roberto-mode.md` (engineering) + `behavior/roberto-voice.md` (voce) |
| Rules | `rules/constitution.md` + `rules/best-practices.md` |
| Agents | `agents/` — baccio, rex, luca, thor, socrates, wanda, roberdan-twin |
| Skills | `skills/` — verify-done, ship, review, sync, auto-checkpoint |
| Hooks | `hooks/` — main-guard, bash-guard, verify-done, autofmt, post-task-sync |
| Loop | `loop/loop-protocol.md` |
| Wrapper per-platform | `platforms/` (generati da `bin/sync.sh --emit-only`) |
| Bundle web | `bin/make-bundle.sh` → doc incollabile (esclude `private/`) |

**Install (gated):** `bin/sync.sh --install` non sovrascrive un `~/.claude/CLAUDE.md`
esistente — stampa il blocco-puntatore da aggiungere a mano. Push su GitHub: deferred.

## Privacy

`private/` è gitignored: contiene il dossier Microsoft-confidenziale (clienti,
deal, persone) e non entra mai in git né in alcun bundle pubblico. Solo la
voce/stile non sensibile è committata.
