# memory-protocol — memoria durevole cross-platform

Contratto unico di memoria per **ogni** platform (Claude/Copilot/Codex/web). La memoria
NON vive in silo per-tool. Vedi [[ADR-0001]].

## Dove vive

| Layer | Path | Ruolo |
|---|---|---|
| Source-of-truth | **vault** `~/Obsidian/Roberdan's Vault`, note `type: agent-learning`, cartella `agent-learnings/` | Durevole, tipata, versionata, cross-tool |
| Staging | `~/.roberdan-os/learnings/inbox/*.md` | Capture per-sessione, no lock |
| Index/recall | gbrain (semantic + keyword) | Ritrovo on-demand, mai caricato tutto in contesto |
| Hot-core | `agent-learnings/_core.md` (≤20 righe) | Le poche verità caricate ovunque |

`~/.claude/.../memory/` = **cache deprecata**. Contenuti migrati nel vault; non è più source-of-truth.

## Tassonomia (5 classi)

| Classe | Cos'è | Auto-eligibile? |
|---|---|---|
| `tool-quirk` | un tool si comporta diversamente dal previsto | sì, se riprodotto ≥2× |
| `correction` | l'utente ha corretto un comportamento | sì, con citazione diretta |
| `decision` | scelta presa con l'utente, non derivabile dal codice | sì, se impatto multi-sessione |
| `capability-gap` | manca qualcosa nel sistema | **no — gate umano** |
| `voice` | come l'utente comunica/decide | **no — gate #6, mai auto-evoluta** |

## Recall (regola operativa)

1. **`gbrain search` keyword PRIMA** (affidabile). `query` semantico droppa i topic sparsi — vedi [[reference-gbrain-semantic-recall-gap]].
2. Scope alla source giusta (`vault` per la memoria), `--detail low`, limit piccolo.
3. Markdown greppabile come fallback finché il recall semantico non è risanato.

## Privacy (hard gate, come codice)

Mai scrivere in memoria contenuto da `~/.roberdan-os/private/` o dati personali/medici
Fight the Stroke / nomi terzi. Check pattern **prima** del write, non a discrezione.
