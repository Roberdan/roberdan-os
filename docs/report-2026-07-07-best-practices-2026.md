# Report — Best-practices pass 2026-07-07 + audit complessivo

**Scope:** goal di Roberto — "controlla tutte le ultime best practices disponibili ad oggi
(7 luglio 2026) applicabili a questo repo (digital twin autonomo), applicale, poi check
complessivo su efficienza, efficacia, autonomia, affidabilità, ottimizzazione costi/token."

**Metodo:** 2 agenti di ricerca paralleli (novità Claude Code/API 2026 da docs ufficiali;
best practices di settore 2025-26 con fonti datate) → gap analysis contro il repo → applicazione
in 3 commit di fase → audit @rex + misure dirette → done-gate @thor.

---

## 1. Cosa dice la ricerca (sintesi, fonti nei commit)

**Fonti chiave 2026:** Anthropic *effective context engineering* (2025-09) e *Claude Code best
practices* (living doc); *Scaling Managed Agents* (2026-04, brain/hands/session + event-log fuori
contesto); *Demystifying evals* (2026-01, judge isolati + calibrazione umana); OWASP Agentic Top 10
(12/2025, ASI01 = goal hijacking); Snyk ToxicSkills (02/2026: 36.8% delle 3.984 skill di marketplace
con difetti, 76 maligne); EvilGenie reward-hacking benchmark (2026); Red Hat *delegation over
impersonation* (2026-05); EU AI Act Art. 50 operativo dal **2026-08-02**; Hermes multi-agent kanban
(05/2026, valida il pattern kanban-as-handoff).

**Verdetto della ricerca sul repo:** l'architettura (canone thin + skill on-demand, kanban su file,
done-gate evidence-first, draft-not-send, privacy split, gate umani) **anticipa o eguaglia** la best
practice 2026. I gap reali erano pochi e puntuali — chiusi sotto.

## 2. Applicato (3 commit su main)

| Commit | Cosa | Perché (fonte) |
|---|---|---|
| `638b5e4` | Snippet hook allineato al canone: SessionStart context-inject (nessun matcher ⇒ re-inietta anche post-compact), PreCompact + Stop auto-checkpoint. Fix `hooks/autofmt.sh`: leggeva `CLAUDE_FILE_PATH` (API morta) ⇒ era un no-op silenzioso; ora parse JSON da stdin. | Compaction-resilience + "Wired End-to-End" (regola del repo) |
| `a5d06d5` | `rules/best-practices.md` v3.5.0: sezione **Context & Token Economy** (file sempre-caricati ≤200 righe, JIT retrieval, isolamento subagent, cache discipline, stato su disco, loop runaway = incidente di costo) + **Agent supply chain** (review skill/MCP prima dell'install, re-review a ogni update, mai MCP non-verificati vicino a `private/`). `loop-protocol`: **tool receipts** nel cursor (recovery log ≠ transcript) + verifica su stato vivo, mai sul transcript. `thor` v1.1: gate #10 **Provenance** (anti reward-hacking). `twin` v2.1: **delegation-not-impersonation** + disclosure AI Act Art. 50. | Managed Agents 04/2026; EvilGenie; Snyk 02/2026; Red Hat 05/2026; AI Act |
| `df45992` | `effort: xhigh` nel frontmatter di board/socrates (campo supportato dai subagent nel 2026); symlink root `CLAUDE.md → AGENTS.md` (raccomandazione ufficiale per repo AGENTS.md-native — Claude Code non legge AGENTS.md nativamente). | Docs Claude Code 2026 |

**Fuori repo (macchina di Roberto):** aggiunto hook `PreCompact` → `auto-checkpoint.sh` in
`~/.claude/settings.json` (backup: `settings.json.bak-2026-07-07`).

## 3. Proposte NON applicate (decisione di Roberto)

1. **Slimming del `~/.claude/CLAUDE.md` globale** — il gap di costo n.1. Oggi: **224 righe /
   ~4.400 token**, caricati in OGNI sessione su qualsiasi repo, + `rules/best-practices.md`
   (~1.800) + `~/GitHub/CLAUDE.md` (~230) ⇒ **~6.400 token sempre caricati**. Tre sezioni parlano
   tutte di gbrain (guardrail operativi, "Using & maintaining", "Search Guidance") con overlap
   sostanziale. Proposta: dedup in un'unica sezione gbrain + spostare il dettaglio operativo
   (comandi di indexing, vault-ingest, embed-until-done) in una skill `gbrain-ops` caricata
   on-demand. Target realistico: **~120 righe / ~2.500 token (−45%)** senza perdere regole.
   Non applicato perché `~/.claude` non è versionato (config curata non rigenerabile) e il file
   governa ogni sessione: serve il tuo ok. Nota: la frase "It's a run-time knob, not an agent
   frontmatter field" sull'effort è da aggiornare — dal 2026 il frontmatter degli agenti supporta
   `effort:` (già usato da board/socrates).
2. **Batch API per i job non-interattivi** (−50% sul costo): candidati = evolve watcher, distill
   settimanale, eval run. Oggi girano via CLI interattiva/launchd; il risparmio è reale solo se
   spostati su chiamate API batch — cambiamento architetturale, valutare quando i volumi crescono.
3. **`task_budget` (beta API)** nei loop lunghi quando esce da beta — self-pacing del budget token.
4. **Agent Teams / Workflow multi-agente** per gli audit larghi (es. audit di tutto l'ecosistema a
   fan-out): opt-in esplicito per sessione, costo 10-15×; da usare per gli audit trimestrali, non di
   default.
5. **Identità delegata per i tool esterni** (Red Hat 05/2026): dove possibile, credenziali separate
   per gli agenti (es. token gh dedicato con scope ridotto) così il trail "on-behalf-of" è audibile
   e il blast radius limitato. Si collega alla rotazione del token `gho_` ancora aperta.

## 4. Audit complessivo (misure + @rex)

### Efficienza / costi / token (misure dirette)

| Voce | Misura | Giudizio |
|---|---|---|
| Canone sempre-caricato in-repo (AGENTS.md via symlink) | 11,5 KB ≈ ~2.900 token, 183 righe | OK (entro la soglia; è il file più ad alto segnale del repo) |
| Iniezione SessionStart (hook) | puntatori + board, ~25 righe, `head -24` sul kanban | OK — token-bounded by design |
| Overhead hook per turno (Stop auto-checkpoint) | ~0,23 s, nessun token | OK |
| Agenti (frontmatter+body) | 1,5–4,9 KB l'uno, caricati solo quando invocati | OK |
| Skill canoniche | 1,8–4,9 KB, progressive disclosure via wrapper thin | OK |
| Contesto globale macchina (fuori repo) | ~6.400 token/sessione | **Gap n.1 — proposta §3.1** |
| Job schedulati | evolve: settimanale, card-based (nessuna chiamata LLM diretta); learn: batch | OK — nessun burn unbounded rilevato |

### Efficacia / autonomia / affidabilità

- **Autonomia:** loop protocol + kanban gated + pause/resume con auto-checkpoint a ogni turno +
  re-iniezione post-compact (da oggi) = una sessione può cadere in qualsiasi momento perdendo al
  massimo il turno corrente. I gate umani restano non-automatizzati (corretto: nessuna fonte 2026
  suggerisce di allentarli).
- **Affidabilità:** "No False Done" + thor gate ora con provenance check (il verificatore guarda
  *come* l'artefatto è nato, non solo che esista) + verifica su stato vivo. Il rischio residuo
  principale è il judge-gaming su task lunghi: mitigato da thor fresh-session + receipts.
- **Efficacia:** il Meta-Card Budget (già nel canone) resta il guardrail giusto — il sistema deve
  produrre valore fuori da sé stesso. Questo pass chiude il filone "allineamento 2026"; il prossimo
  lavoro dovrebbe essere external-facing.

### Audit @rex

**Verdetto: APPROVE-WITH-CONCERNS** sui 3 commit di questa sessione — tutti verificati
funzionalmente (autofmt ri-testato via stdin, symlink CLAUDE.md provato non-breaking contro
leak-check/fork-merge/bundle, claim AI Act e effort-frontmatter verificati su fonti esterne).
Finding e risoluzione:

| Sev | Finding | Risoluzione |
|---|---|---|
| HIGH | `effort:` frontmatter contraddiceva `thinking-toolkit.md` ("run-time knob, not a frontmatter field") | Fixato da session B in `96619b6` (passaggio aggiornato: dal 2026 effort È anche un campo frontmatter) |
| HIGH | I "tool receipts" `.agent-state/*.jsonl` sono dichiarati nel canone ma **nessun codice li scrive/legge** (violazione Wired End-to-End) | Linguaggio onesto in loop-protocol + thor gate #10: receipts di oggi = commit di fase evidence-first + audit line delle card kb; il jsonl è formato dichiarato, emitter da wire-are prima di farci affidamento |
| MED | `rules/best-practices.md` (266 righe) viola la sua stessa soglia ≤200 — e il bundle ChatGPT lo concatena verbatim | Scope-note nella regola + duty "prune before adding"; trim rimandato al prossimo canon pass |
| MED | Nessun test copriva il contratto stdin di autofmt (lo stesso motivo per cui il no-op silenzioso era passato inosservato) | `test/test-autofmt.sh` (4 casi: stdin JSON→formatter, file inesistente, stdin degenere, fallback legacy) wired in validate.sh |
| MED | I settings live non montano main-guard/autofmt/verify-done/post-task-sync (documentato "manual/approve" in sync.sh — limite onesto, non bug) | Segnalato qui: decisione di Roberto se installarli; `pre-completion-gate.sh` (curato, fuori repo) copre già parte di verify-done |
| LOW | I commit feature erano senza CHANGELOG/VERSION | Chiuso da questa release v2.7.0 |

### Nota di processo — due sessioni, stesso goal, stesso checkout

Durante il pass una **seconda sessione Claude** (session B) ha lavorato lo stesso goal sullo
stesso checkout. Convergenza indipendente sulle stesse conclusioni (effort frontmatter, fix
hook, compressione canone) = buon segnale di robustezza del metodo; ma anche righe `effort:`
duplicate (race sui file) e rischio di collisione sulla release. Coordinazione riuscita via
file disgiunti (session B ha esplicitamente lasciato thor/twin a questa sessione) e attesa di
quiescenza del tree prima di committare. **Lezione salvata in memoria**: prima di
`git add`/`commit` in questo repo, controllare writer concorrenti (`git status` + diff dei
file non propri), stage di path espliciti, mai `git add -A`.

## 5. Done-gate

**@thor: PASS (F-01…F-10 tutti verificati empiricamente)** — matrice completa nel transcript
della sessione. Punti chiave: 8 commit su main con tree pulito a parte i file di release;
`test-autofmt.sh` PASS e wired in validate.sh (`ok: autofmt receives files via stdin JSON`);
symlink CLAUDE.md verificato; un solo `effort:` per agente con i valori previsti; canone
coerente (nessuna traccia della vecchia frase "not a frontmatter field"); PreCompact hook
live con backup pre-modifica; **`validate.sh` ALL GREEN** rieseguito end-to-end da thor stesso.
CI sul commit di release: vedi badge/`gh run` (verificata prima di dichiarare "released").
