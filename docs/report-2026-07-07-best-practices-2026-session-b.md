# Report — Best practices 2026, sessione B (audit parallelo + fix disgiunte)

**Data:** 2026-07-07 · **Nota di coordinamento:** il goal girava in DUE sessioni parallele.
Questa (B) ha rilevato l'altra (A) in-flight su `bin/sync.sh`, `hooks/autofmt.sh`,
`loop/loop-protocol.md`, `rules/best-practices.md`, `agents/{thor,twin}.md` e ha applicato
SOLO fix su file disgiunti. Il report principale di A: `report-2026-07-07-best-practices-2026.md`.
Qui: le fix applicate da B (già nel working tree), i finding B non coperti altrove, le fonti.

**Metodo B:** 3 agenti paralleli — ricerca web (~90 fonti, verifica adversariale), audit @rex
full-repo (Opus), feature-drift Claude Code su doc ufficiali — più misure dirette.

---

## 1. Fix APPLICATE da questa sessione (verificate: bash -n ✅, run live ✅, validate.sh ALL GREEN ✅)

Da audit @rex:

| Fix | File | Cosa |
|---|---|---|
| M1 anchor rotta `#gate-umani`→`#human-gates` | `agents/wanda.md`, `agents/board.md` | restano: `loop-protocol.md:68`, `bin/sync.sh:101` (in-flight A), `docs/federated-kanban-migration-2026-07-05.md:41` |
| M2 contraddizione Convergio | `behavior/roberto-mode.md` | done-condition 3 + principi 7/8: "witness obbligatorio" → **optional observer** (allineato ad AGENTS.md/loop-protocol); mai bloccati su un daemon spento |
| M3 header overclaim | `hooks/post-task-sync.sh` | dichiara ciò che fa (wrapper+leak-check), non "sync 3 sistemi" |
| M4 banner PAUSED cry-wolf | `hooks/context-inject.sh` | auto-checkpoint → banner soft; PAUSED solo su pausa esplicita. Verificato live |
| M5 honesty note `--thor` | `AGENTS.md` § kanban | stesso disclaimer di `--by` (discipline gate, non security boundary, manual path) |
| M6 commit non-atomico + race | `ontology/curate.sh` | commit per-candidato; quarantena consumata SOLO a commit riuscito; failure a video |
| L2 version-grep fragile | `hooks/verify-done.sh` | `_manifest_version()`: versione top-level, non primo match |
| L3 eval stantii | `eval/results/report.md` | staleness note (pre v2.4–v2.6) |

Da ricerca 2026:

| Fix | File |
|---|---|
| `effort:` frontmatter (leva costo/qualità #1 2026; Claude Code lo supporta accanto a `model:`) | `baccio,luca,rex → high` · `board,socrates → xhigh` · `wanda → medium` (`thor`,`twin` → sessione A) |
| Doctrine effort corretta ("non è frontmatter" era diventato falso) | `behavior/thinking-toolkit.md` § Fable · `~/.claude/CLAUDE.md` § Effort |
| Model table 2026 (Sonnet 5, Fable 5 default main, dedup riga Opus) | `~/.claude/CLAUDE.md` (backup: `CLAUDE.md.bak-2026-07-07`) |

## 2. Finding B ad alto impatto NON ancora applicati (per A / Roberto)

1. **H1 (@rex, HIGH)** — `bin/sync.sh:159-168` emette `settings-hooks.json` con `$RDA_OS`,
   variabile definita in NESSUN file del repo → su reinstall/fork i guard di sicurezza
   (main-guard, bash-guard) si espandono a `/hooks/...` e muoiono in silenzio. `bootstrap.sh:59`
   usa già il path assoluto: allineare + assert in `validate.sh` ("nessuna $VAR indefinita
   nell'artifact"). *(sync.sh è in-flight in A.)*
2. **Test immutabili per il produttore** (arXiv 2606.06223, reward-hacking del done-gate): una
   riga in roberto-mode/verify-done — chi produce il lavoro non tocca test/criteri.
3. **E2E nel done-gate** (Anthropic "effective harnesses", 2025-11): @thor preferisca il flusso
   reale (browser/curl) agli unit test quando esiste superficie runtime.
4. **Cache-aware ordering** (read=0.1x): canone/persona come prefix stabile; variabile in coda.
5. **Batch API per eval/** (−50%) + giudici "Unknown", una dimensione per giudice,
   golden-trajectory a checkpoint (Anthropic "demystifying evals", 2026-01).
6. **defer_loading / Tool Search** sui MCP pesanti (gbrain ~100 tool): −85% tool-tax/turno.
7. **L1 (@rex)** — saggio privacy triplicato (AGENTS.md, leak-check.sh, update-denylist-hashes.sh)
   → AGENTS.md tiene 3 righe + pointer. Rivalutare anche il peso del `~/.claude/CLAUDE.md`
   globale (≈3.2k token fissi/sessione).
8. **Re-run eval** post-fix: il run 07-02 dava constitution −1.5 e AGENTS.md −2.0 (gap B−A):
   dopo la compattazione, rimisurare — è il criterio-guida del taglio.
9. **Skills-standard** (agentskills.io): valutare SKILL.md nativi multi-harness al posto dei
   wrapper; rinominare `skill.md`→`SKILL.md` nel repo (sync.sh installa già col nome giusto,
   i forker su Linux no). MAI affidarsi a `allowed-tools` cross-tool.
10. Igiene: L4 (factory vs main-guard: worktree per task di codice), L5 (log launchd in
    `$RDA_HOME/logs/`, non `/tmp`).

## 3. Ciò che la ricerca CONFERMA (non toccare)

@thor fresh-session (arXiv 2603.16244: verifica in context separato > self-critique; il debate
multi-agente produce falso consenso — cautela sul consenso di @board: tenerlo adversariale);
gate blast-radius; draft-not-send + dossier local-only; "mai inventare" (arXiv 2601.11000: la
personalizzazione AUMENTA le allucinazioni); identità a livelli; resume idempotente
(prerequisito del checkpointing sicuro); stato durevole su file.

**Non adottare** (con rationale): Managed Agents (server-side state vs local-first), sampling
MCP (deprecato in RC 2026-07-28), Fast mode (2x costo, nessun SLA), extended thinking su Haiku,
MCP in-process SDK.

## 4. Valutazione per asse (@rex pre → post fix B; A aggiungerà le sue)

| Asse | Pre | Post B | Leva successiva |
|---|---|---|---|
| Efficienza | 7 | 7 | dedupe L1 + CLAUDE.md globale |
| Efficacia | 7 | 7.5 | re-run eval su canone corrente |
| Autonomia | 6 | 6.5 | H2 (in corso in A) |
| Affidabilità | 5 | 6 | **H1** (il buco più grosso) |
| Costi/token | 8 | 8 | caching/batch/defer-loading |

**Sintesi:** architettura confermata allo stato dell'arte 2026; il gap è di *enforcement*
(ciò che il canone promette dev'essere wired e testato da validate.sh) e di *leve economiche*
2026 non ancora attivate (effort ✅ · caching/batch/defer ⬜). Nessun cambio architetturale.

---

## Addendum (2026-07-07 sera) — bug kb scoperto sul campo

**`kb add` collide sugli ID al secondo:** l'ID card è `%y%m%d-%H%M%S`; N add nello stesso
secondo (es. da uno script) producono lo STESSO id e le card si sovrascrivono in silenzio
(6 card → 1 sopravvissuta, osservato su Fabrica). Fix proposto in `kanban/kb.sh`: suffisso
di unicità (contatore o `%N`ms) o guard "id esiste già → bump". Workaround: `sleep 1.1` tra add.

**`kb lint` rotto:** invoca `~/.local/kanban/lint-cards.sh` che non esiste (probabile path
drift nell'install: lo script vive nel repo, non in `~/.local/kanban/`). Il lint schema
runner:/human_gates: dichiarato nell'help è quindi non eseguibile. Fix: risolvere il path
dal repo (`$RDA_OS/kanban/…`) o installare lo script accanto a `kb`.
