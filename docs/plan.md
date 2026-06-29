# Piano — `roberdan-os`: sistema agentico unico, cross-platform, loop-autonomo

## Context

Roberto ha ~200+ skill, ~300+ agenti, hook e persona sparsi su 13+ repo, in 3+ formati, senza fonte canonica. Lo stesso agente (baccio, ali…) esiste in 4-6 copie divergenti; la config globale `~/.claude` non è nemmeno versionata. Due audit (2026-06-28 skill/agent, 2026-06-29 strategico Opus) hanno mappato il problema: non è scarsità, è **superficie di manutenzione vs uso reale** — probabilmente usi ~6 agenti su 87.

**Decisione presa con l'utente:** creare un **nuovo repo git dedicato `~/GitHub/roberdan-os`** come fonte canonica unica. Ricostruire da zero *solo ciò che serve* (greenfield), tagliando i riferimenti morti — **senza toccare né rimuovere nulla dai repo legacy** (continuano a funzionare come sono). Il nuovo sistema deve funzionare su **Claude Code, GitHub Copilot (CLI + VS Code), Codex, ChatGPT / Claude web** (target primari). **Hermes deprioritizzato** (non emerso nello scan di sistema; formato non verificato) — fuori dai must-work per ora, riattivabile con un gate "verifica capabilities". Ogni agente deve operare in **loop autonomo** allineato al modo di lavorare di Roberto (autonomia totale + evidence-first + verifica empirica).

### Due emisferi del canone comportamentale
Il sistema cattura **due facce complementari** di Roberto, non una:
- **Operating / engineering** (`behavior/roberto-mode.md`, già costruito da 15.849 messaggi): come gli agenti *operano* sul codice — autonomia, evidence-first, done-criteria, quality gate.
- **Voice / relationship** (nuovo, dal Copilot aziendale Microsoft — `~/Downloads/SKILL.md` + `profile.md`): come gli agenti *comunicano nella sua voce* e *decidono come lui* — drafting email/Teams, follow-up clienti, triage, decision-lens (relationship-before-transaction, bias-to-action, protect family/teaching, right-altitude), M.I.R.R.O.R.S., sign-off "Roberdan"/"Roberto", bilingue IT/EN/ES.

**Gate privacy (decisione utente — "split"):** lo *stile/voce* (non sensibile) entra nel canone committato (`behavior/roberto-voice.md`); il *dossier* con clienti/deal/persone Microsoft-confidenziali (i nomi reali — clienti, deal, contratti, UPN — restano solo nel dossier) **NON entra in git** — vive solo in `~/.roberdan-os/private/roberto-profile.md` (gitignored, local-only), letto a runtime ma mai committato né incluso in alcun bundle pubblico. La denylist concreta vive in `private/.denylist` (anch'essa local-only).

**Outcome atteso:** un'unica fonte versionata da cui ogni tool consuma lo stesso comportamento; agenti che si auto-verificano e auto-rilanciano senza polling manuale; affidabilità garantita da stato durevole su file (Convergio resta orchestratore *opzionale*, non dipendenza).

### Principio architetturale
**Conoscenza centralizzata, esecuzione per-platform, comportamento unificato da `roberto-mode`.**
`AGENTS.md` è lo standard universale (Codex, Copilot, Hermes, Cursor lo leggono nativamente); CLAUDE.md e copilot-instructions.md diventano puntatori thin (il repo `convergio` già usa il pattern symlink CLAUDE.md→AGENTS.md — lo adottiamo come modello). La logica vive una volta sola; i wrapper runtime sono generati per ogni tool.

### Sulla affidabilità senza Convergio (risposta alla domanda)
Il loop è affidabile se lo stato è **durevole su file** (SQLite/jsonl a path noto) + **resume idempotente** + **terminal-condition** verificate da hook su ground truth (git/gh/cargo). Nessun daemon richiesto per il caso single-agent. Convergio v3 (`:8420`, 36 MCP actions) entra solo come **osservatore/orchestratore opzionale** che *legge* lo stesso state file — adottabile a costo zero in futuro per dispatch cross-agente, ma mai single point of failure. Design daemon-optional.

---

## Struttura target del repo `~/GitHub/roberdan-os`

```
roberdan-os/
  README.md                    # cos'è, come ogni tool lo consuma, comando di install
  AGENTS.md                    # entry universale — ogni tool legge questo
  behavior/
    roberto-mode.md            # emisfero ENGINEERING (da ~/.claude/skills/roberto-mode)
    roberto-voice.md           # emisfero VOICE/relationship (da Downloads/SKILL.md, scrubbed)
  agents/                      # set minimo curato — prosa provider-neutral + frontmatter claude opzionale
    baccio.md  rex.md  luca.md  thor.md  socrates.md  wanda.md  roberdan-twin.md
  private/                     # NON in git (.gitignore) — installato in ~/.roberdan-os/private/
    roberto-profile.md         # dossier Microsoft-confidenziale (clienti/deal/persone) — local-only
  rules/
    best-practices.md          # regole qualità canoniche (da ~/.claude/rules/best-practices.md)
    constitution.md            # radice etica slim (distillata da MyConvergio CONSTITUTION.md)
  skills/                      # logica in markdown puro; i wrapper si generano
    verify-done/skill.md  ship/skill.md  review/skill.md  sync/skill.md  auto-checkpoint/skill.md
  loop/
    loop-protocol.md           # contratto loop standard (state, terminal-condition, escalation, resume)
  hooks/                       # guard globali parametrizzati (no path hardcoded)
    main-guard.sh  bash-guard.sh  verify-done.sh  autofmt.sh  post-task-sync.sh
  platforms/                   # wrapper thin, generati da bin/sync.sh
    claude/   copilot/   codex/   chatgpt/   hermes/
  bin/
    sync.sh                    # genera i wrapper dal canone + installa in ~/.claude e nei target
    make-bundle.sh             # concatena SOLO canone committato → 1 doc incollabile (esclude private/)
  test/
    validate.sh                # CI: lint frontmatter, link check, drift wrapper-vs-canone
```

---

## Fasi di implementazione

### Fase 0 — Bootstrap repo
- `git init ~/GitHub/roberdan-os`, struttura cartelle, `README.md`, `.gitignore`.
- `AGENTS.md` root: indice + sezioni `## Behavior` (`→ behavior/roberto-mode.md` + `→ behavior/roberto-voice.md`), `## Agents`, `## Rules`, `## Loop Protocol`. È il file che ogni tool legge.
- `.gitignore`: esclude `private/` (il dossier confidenziale non deve mai entrare in git history).
- Applicare repo-settings dei best-practices (merge-commit only) quando andrà su GitHub.

### Fase 1 — Contenuto canonico (la fonte unica)
- **behavior/roberto-mode.md** ← copia canonica da `~/.claude/skills/roberto-mode/SKILL.md` (già costruito da 15.849 messaggi). Emisfero *engineering*; tutti i runtime la referenziano.
- **behavior/roberto-voice.md** ← distillato da `~/Downloads/SKILL.md` (emisfero *voice/relationship*): le 6 sezioni (voice non-negotiables, language, decision-lens, delegation playbooks, guardrails, few-shot) **con i few-shot scrubbed** dei nomi cliente/persona reali → sostituiti con placeholder generici (`[Partner]`, `[Collega]`). Lo stile resta, i dati confidenziali no.
- **private/roberto-profile.md** (NON committato) ← copia integrale di `~/Downloads/profile.md` (identity, portfolio FY26, key people, M.I.R.R.O.R.S., "Good Morning"/"clawpilot"). Installato da `sync.sh` in `~/.roberdan-os/private/`; il twin lo legge a runtime se presente, altrimenti degrada con un avviso. Mai in git, mai in bundle.
- **agents/** — 7 persona curate, schema da `rex.md` (il più pulito). Frontmatter normalizzato: `name, description, model, tools, providers, constraints, version, maturity`. `model` sempre quotato. Blocco etico condiviso → riferimento a `rules/constitution.md`, non copia-incollato.
  | Canonical | Ruolo | Consolida |
  |---|---|---|
  | baccio | Architect + coding | — |
  | rex | Code + ecosystem review | rex(235r) + sentinel(249r) |
  | luca | Security | — |
  | thor | QA / verify-done guardian | — |
  | socrates | First-principles (pre-decisione) | antonio/domik/matteo |
  | wanda | Orchestrator del loop | ali |
  | **roberdan-twin** | Digital twin: drafting/triage/decide nella voce di Roberto | da `Downloads/SKILL.md` |
  - **roberdan-twin** legge `behavior/roberto-voice.md` (canone voce) + `private/roberto-profile.md` (dossier, se presente). Guardrail propri: **draft-not-send** per esterni/contrattuali/leadership, **mai inventare** nomi/date/cifre, rispetta i blocchi personali (sera/famiglia/Polimi). Eredita i gate umani #3/#6.
  - Le persona C-suite (amy/satya/dan…) **non vengono ricreate** in roberdan-os (restano nei legacy intatte). Comando di verifica uso reale in Appendice se vorrai recuperarne qualcuna.
- **rules/best-practices.md** ← canonica da `~/.claude/rules/best-practices.md`.
- **rules/constitution.md** ← distillata slim da `MyConvergio/.claude/agents/core_utility/CONSTITUTION.md` (8 articoli → essenza: Identity Lock, evidence-based Done, Thor-only done, accessibilità). Niente `MICROSOFT_VALUES.md` (Convergio non è Microsoft).

### Fase 2 — Skill canoniche (solo le cross-platform-degne)
Logica in `skills/<nome>/skill.md` (markdown puro, checklist tool-agnostica). Porto solo quelle ad alto uso e basso accoppiamento al runtime:
- **verify-done** (evidence-first gate — il tuo principio cardine)
- **ship** (git+gh, platform-agnostic)
- **review** (code review)
- **sync** (allinea i 3 sistemi vault+cvg+repo)
- **auto-checkpoint** (il "kit loop" portatile — vedi Fase 5)

NON porto le CC-runtime-bound (browse, qa, ios-*, design-*, connect-chrome): restano gstack su Claude Code.

### Fase 3 — Hook globali parametrizzati
Promuovo a `roberdan-os/hooks/` (poi installati in `~/.claude/settings.json`), togliendo i path hardcoded. Riconcilio con `pre-completion-gate.sh` già esistente su Stop e con la suite hook che MyConvergio già referenzia.
| Hook | Origine | Modifica |
|---|---|---|
| `main-guard.sh` | MirrorBuddy | rinominare env-var escape → generica; già worktree-aware |
| `bash-guard.sh` | MirrorBuddy | tenere solo metà git/gh-safety (universale); npm-rules restano per-repo |
| `verify-done.sh` | VirtualBPM | parametrizzare version-file location |
| `autofmt.sh` | VirtualBPM | repo-root detection invece di path frontend hardcoded |
| `post-task-sync.sh` | **nuovo** | Stop/SubagentStop: rigenera repo-docs + cvg plan da vault, commit `chore(sync)` — meccanizza l'anti-drift dei 3 sistemi |
Protocollo: JSON-decision (`hookSpecificOutput`) per i guard; stile silent per formatter/notifier. Restano repo-local: `notify-app.sh`, `post-edit-ts.sh`.

### Fase 4 — Proiezioni per-platform + `bin/sync.sh`
`sync.sh` genera i wrapper dal canone e li installa. Niente conoscenza copiata a mano — solo generata.
| Platform | Come consuma | Wrapper generato |
|---|---|---|
| **Claude Code** | nativo | `~/.claude/skills/*/SKILL.md` (thin → `read skills/X/skill.md`), `~/.claude/agents/*.md` (symlink), snippet `settings.json` hook, `~/.claude/CLAUDE.md` → punta ad AGENTS.md |
| **Copilot CLI + VS Code** | no runtime SKILL.md | `.github/copilot-instructions.md` (thin → AGENTS.md), skill come `.prompt.md` |
| **Copilot app standalone** | da verificare | **verifica al primo install** se consuma un instructions-file repo-level; finché non confermato, tratto come "da verificare" (no assunzione silenziosa) → fallback bundle incollabile |
| **Codex** | AGENTS.md nativo | `AGENTS.md` letto direttamente; snippet config |
| **ChatGPT / Claude web** | no filesystem | `bin/make-bundle.sh` → 1 doc incollabile (roberto-mode + **roberto-voice** + best-practices + agents index) per Custom Instructions / Project. **Mai** include `private/roberto-profile.md` |
| **Hermes** | _deferred_ | non costruito ora — gate "verifica capabilities" prima di proiettarlo. AGENTS.md resta già compatibile se in futuro lo legge nativamente |
Per i repo: ogni repo adotta il pattern symlink `CLAUDE.md → AGENTS.md` (modello `convergio`), e `AGENTS.md` referenzia `roberdan-os` via blocco `## Behavior: [[roberto-mode]]`.

### Fase 5 — Loop autonomy
- **loop/loop-protocol.md** — contratto standard incluso in ogni AGENTS.md loop-aware:
  ```
  state: <state.db structured> + .agent-state/<task>.jsonl (cursor)
  terminal-condition: <check empirico job-specific, es. "cargo test green + CI #N pass">
  checkpoint: 1 commit per fase, messaggio evidence-first (SHA/PR/CI in ogni update)
  escalation: 2 tentativi falliti stesso problema → opus, logga reason
  sync-on-iteration: post-task-sync (vault+cvg+repo) a fine di OGNI fase
  resume: leggi stato all'avvio, riparti dall'ultimo step done, mai rifare
  stuck: 2 pass senza progresso → STOP, segnala cosa è wedged, non loopare
  ```
- **skills/auto-checkpoint** — kit iniettabile in qualsiasi sessione: scrive/legge stato durevole, definisce terminal-condition, abilita auto-resume + auto-escalation.
- **State store daemon-optional:** SQLite a path noto (`~/.convergio/v3/state.db` se presente, altrimenti `~/.roberdan-os/state.db`). RFC3339 timestamps. Leggibile sia dagli hook sia da Convergio se attivo — ma il loop non dipende dal daemon.
- **Per-platform driver:**
  - Claude Code: `/loop` + `ScheduleWakeup` per attese esterne (CI/deploy/embed) — `submit → wakeup +Nmin → check terminal-condition → done | re-arm`.
  - Altri: launchd/cron leggono lo stesso checkpoint file.
- **Segnalazione proattiva:** ogni checkpoint = update evidence-first (`[fase 3/7 ✓] commit a1b2c3d · CI #4821 green · next: …`), mai "sto lavorando".

### Fase 6 — Validazione + CI + dogfood
- **test/validate.sh**: lint frontmatter agenti, link check, **drift check** (wrapper rigenerati == committati), shellcheck hook, **leak check** (nessun nome cliente/persona confidenziale nel canone committato o nei bundle — denylist da `private/`).
- GitHub Actions: esegue validate.sh su ogni PR; merge-commit only.
- **Dogfood:** girare un task reale end-to-end in loop su Claude Code (es. un fix con `/loop`) verificando checkpoint, resume dopo kill, post-task-sync, segnalazione evidence-first.

---

## Gate umani (cosa NON automatizzare)
Autonomia ≠ black box. Questi passano **sempre** da Roberto (messaggio diretto, non relay di un coordinator):
1. Merge su `main` con impatto su branch-protection / security / license / release-infra
2. Force-push su `main`
3. Spesa reale / email esterne / pubblicazioni pubbliche
4. Cancellazione dati non-rigenerabili (vault notes, source gbrain, repo history)
5. Decisioni strategiche/prodotto con tradeoff non-ovvi (agente propone con evidence, Roberto decide)
6. Materiale che esce a nome Roberto / Fight the Stroke
7. Cambi architetturali >4 file con invarianti cross-cutting

---

## File chiave da creare (rappresentativi)
- `~/GitHub/roberdan-os/AGENTS.md` — entry universale
- `~/GitHub/roberdan-os/behavior/roberto-mode.md` — da `~/.claude/skills/roberto-mode/SKILL.md`
- `~/GitHub/roberdan-os/behavior/roberto-voice.md` — da `~/Downloads/SKILL.md` (few-shot scrubbed)
- `~/GitHub/roberdan-os/private/roberto-profile.md` — da `~/Downloads/profile.md` (gitignored, local-only)
- `~/GitHub/roberdan-os/agents/{baccio,rex,luca,thor,socrates,wanda,roberdan-twin}.md`
- `~/GitHub/roberdan-os/rules/{best-practices,constitution}.md`
- `~/GitHub/roberdan-os/loop/loop-protocol.md`
- `~/GitHub/roberdan-os/skills/{verify-done,ship,review,sync,auto-checkpoint}/skill.md`
- `~/GitHub/roberdan-os/hooks/{main-guard,bash-guard,verify-done,autofmt,post-task-sync}.sh`
- `~/GitHub/roberdan-os/bin/{sync.sh,make-bundle.sh}`
- `~/GitHub/roberdan-os/test/validate.sh`

## Riuso (non reinventare)
- `~/.claude/skills/roberto-mode/SKILL.md` (canone comportamentale già pronto)
- `~/Downloads/SKILL.md` + `~/Downloads/profile.md` (digital twin Microsoft — voce + dossier, da splittare canone/private)
- `~/.claude/rules/best-practices.md` (regole qualità già scritte)
- `MyConvergio/.claude/agents/core_utility/CONSTITUTION.md` (radice etica da distillare)
- `MyConvergio/.../technical_development/rex.md` (schema frontmatter canonico)
- Hook esistenti MirrorBuddy/VirtualBPM (da parametrizzare, non riscrivere)
- `convergio` symlink pattern CLAUDE.md→AGENTS.md (modello da propagare)
- `~/.claude/hooks/pre-completion-gate.sh` (già attivo su Stop — riconciliare)

## Verifica end-to-end
1. **Install:** `roberdan-os/bin/sync.sh` → controlla che `~/.claude/skills/`, `~/.claude/agents/`, `settings.json` hook siano generati e validi (`claude` parte senza errori).
2. **Claude Code:** invoca `/roberto-mode` e un agente (es. `@rex`) → verifica che leggano dal canone.
3. **Copilot:** apri un repo con `.github/copilot-instructions.md` generato → conferma che Copilot CLI carica il profilo.
4. **Codex:** in un repo con `AGENTS.md` → conferma che Codex lo rispetta.
5. **ChatGPT/Claude web:** `make-bundle.sh` → incolla il bundle in un Project → conferma comportamento allineato. **Verifica privacy:** `grep` nel bundle generato conferma 0 nomi cliente/persona reali (nessun leak da `private/`).
6. **Twin:** invoca `roberdan-twin` con un task di drafting → conferma voce corretta (warm-open, next-step, sign-off), draft-not-send rispettato, dossier letto da `~/.roberdan-os/private/` (o degrado pulito se assente).
7. **Privacy gate:** `git status`/`git log` di roberdan-os non mostrano mai `private/`; `.gitignore` lo esclude; `test/leak-check.sh` (grep `-iE -f private/.denylist`) = 0 risultati su canone e bundle.
8. **Loop:** task reale con `/loop` su Claude Code → uccidi il processo a metà → verifica resume da checkpoint, post-task-sync, e update evidence-first.
9. **Drift:** `test/validate.sh` verde (wrapper in sync col canone).
