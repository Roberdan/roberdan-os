# ontology-protocol — promozione + igiene memoria (single-writer)

**Estende** l'ontologia del vault (Tolaria), non un nuovo store. Un solo processo seriale
tocca il vault (lock AutoGit). Vedi [[ADR-0001]], [[memory-protocol]].

## Promozione (quarantena → vault)

`ontology/curate.sh` (launchd, single-writer):
1. Legge `~/.roberdan-os/learnings/quarantine/`.
2. Per ogni candidato eligibile (vedi [[learn-protocol]] gate): crea/aggiorna nota
   `type: agent-learning` in `agent-learnings/`, con frontmatter Tolaria
   (`belongs_to`/`workspace`/`supersedes`) → filtrabile/eliminabile in blocco.
3. Commit AutoGit singolo, retry su `.git/index.lock`. Mai concorrente.
4. Refresh gbrain (index della nota nuova).

## Igiene periodica (triggerata, human-gated)

NON auto-merge/auto-delete (lossy + irreversibile, gate #4). Il job **propone**:
- **dedup** semantico (gbrain near-dup) → lista merge candidati.
- **tombstone retire**: fatti `RISOLTO`/pre-v3 → archivio `agent-learnings/_archive/`.
- **compressione hot-core**: `_core.md` ≤20 righe, le righe morte costano token ovunque.
Merge/delete restano decisione umana. Output = un report di proposte, non azioni.

## Confini (cosa NON fa)

Niente relazioni auto-generate tra learning (edge spuri — vedi
[[reference-gbrain-wikilink-gap]]). Niente motore-ontologia bespoke. Niente
auto-aggiornamento real-time. **Riuso > struttura nuova.**
