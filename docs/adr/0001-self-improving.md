# ADR-0001 — roberdan-os auto-migliorante: evolve / learn / ontology

**Status:** Accepted (2026-06-30) · **Decisori:** Roberto + advisor (baccio/socrates/rex)

## Contesto

roberdan-os ha il loop *per-task* (`loop/loop-protocol.md`, `skills/auto-checkpoint`) ma
non un *meta-loop*: non si tiene aggiornato sui tool, non distilla learning dopo le
interazioni, non riorganizza la memoria. Obiettivo: renderlo **auto-migliorante e lo
standard di default**, senza violare il principio cardine — *conoscenza centralizzata,
esecuzione per-platform, daemon-optional* — né i gate umani.

**Vincolo cross-platform (correzione Roberto):** la memoria durevole vive nel **vault
Obsidian** (markdown leggibile da ogni tool, ontologia Tolaria, indicizzato gbrain),
NON in `~/.claude/.../memory/` (silo Claude-only → deprecato a cache, contenuti migrati).

## Decisioni

| Componente | Decisione | Razionale |
|---|---|---|
| **Scheduling** | **launchd** invoca `run.sh` plain (cron-swappable). Mai `ScheduleWakeup`/`CronCreate` per job periodici | Deve scattare anche con Claude chiuso (Copilot/Codex). I job gbrain già usano launchd |
| **learn/** | **Capture ≠ distill.** Capture = cursor `.jsonl` per-platform → flush in staging inbox `~/.roberdan-os/learnings/inbox/` (no lock). Distill = batch periodico → candidati in **quarantena** | Disaccoppia portabilità da rumore. NO distill per-`Stop` (Claude-only + invasivo) |
| **ontology/** | **Estendi il vault, nessun nuovo store.** Tolaria = autorità schema (`type: agent-learning`); gbrain = dedup semantico. Job **single-writer** promuove candidati → note tipate | socrates: auto-ontologia = over-engineering + 4° store che drifta. Riuso > reinvenzione |
| **Recall** | gbrain semantic search sul vault (+ markdown greppabile). Nessun indice caricato ogni sessione | Cross-platform, già wired |
| **evolve/** | Watcher **settimanale**: changelog Claude/Copilot/Codex → diff vs capability → **solo draft** in `proposals/`, con citazione fonte (URL+versione+data) | Cross-platform via launchd |

## Tagliato (over-engineering — socrates)

Ontologia auto-aggiornante in tempo reale · relazioni auto-generate tra learning ·
auto-merge/auto-compressione senza gate · motore-ontologia bespoke sopra Tolaria.
Sostituiti da: **1 type + 1 job di igiene human-gated** che riusa i tipi esistenti.

## Invarianti (enforcement meccanico, non promessa)

1. **Mai auto-applicare** cambi a `behavior/ rules/ agents/ AGENTS.md` — evolve produce
   **solo draft**. Path-allowlist in `test/validate.sh`: auto-commit consentito solo su
   `platforms/` (wrapper deterministici).
2. **Single-writer sul vault** (Tolaria AutoGit `.git/index.lock`) — capture concorrente
   scrive solo nella staging inbox; un solo processo seriale fa flush.
3. **Privacy come codice:** deny-list pattern (dossier `~/.roberdan-os/private/`, dati
   personali/medici FtS) verificata **prima** di ogni write, non a discrezione del modello.
4. **Promozione gated:** candidato → nota influente solo dopo corroborazione (N sightings
   o conferma umana). Classe `voice` mai auto-evoluta (gate #6).
5. **No-hallucination:** ogni proposta evolve cita la fonte o non esiste.

## Rischi → mitigazione

| Rischio | Mitigazione |
|---|---|
| Drift identità/comportamento | evolve solo-draft + path-allowlist in validate.sh |
| Learning poisoning (rinforzo errori) | corroborazione N-sightings + review periodica `@thor`/umana |
| Inflazione/rumore memoria | dedup-before-write via `gbrain search`; igiene periodica; hot-index minimo |
| Embedding provider down | **scoperto 2026-06-30:** openai=quota-zero, zembed=no-key → recall semantico fermo. Vedi [[provider locale Ollama]] come unica via sostenibile |

## Conseguenza

Sistema auto-**proponente**, mai auto-**applicante** sul comportamento. Gate #6/#7
preservati per costruzione. Tassonomia learning: `tool-quirk · correction · decision ·
capability-gap · voice`.
