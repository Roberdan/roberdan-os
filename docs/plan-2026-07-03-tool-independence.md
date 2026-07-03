# Piano 2026-07-03 — tool-independence (analisi Fable → esecuzione opus/sonnet)

Goal (Roberto, /goal): il sistema deve funzionare **indipendentemente dal modello o tool** —
Claude, Copilot, ollama locale, opencode, hermes, codex, Warp o qualsiasi altro sistema agentico —
come digital twin affidabile per business, documenti, ragionamento e gestione repo, con goal
complessi, auto-ottimizzazione, auto-apprendimento, aggiornamento continuo, leva su gbrain/gstack.

## Analisi (Fable, 2026-07-03) — sintesi evidence-first

**La scommessa architetturale è stata validata dall'industria.** AGENTS.md — scelto come canone a
giugno — è oggi lo standard de-facto letto NATIVAMENTE da: OpenAI Codex CLI (è il suo file nativo,
gerarchia `~/.codex/AGENTS.md` → repo), GitHub Copilot (coding agent da ago 2025 + CLI, con
fallback a CLAUDE.md), Cursor, opencode (formato nativo, fallback a `~/.claude/CLAUDE.md`), Warp
(AGENTS.md nativo, WARP.md legacy), Google Jules, e **hermes** (Nous Research hermes-agent, che
legge AGENTS.md come workspace instructions — verificato nel package installato). Anche SKILL.md è
diventato portabile: Codex, Gemini CLI, Cursor lo supportano ufficialmente; opencode legge
direttamente `.claude/skills/*/SKILL.md`. Fonti primarie citate nel report di ricerca in sessione.

**Il gap non è l'architettura: è la distribuzione.** Verificato su questa macchina:

| Tool | Installato | Collegato al canone OGGI | Meccanismo disponibile |
|---|---|---|---|
| Claude Code | ✅ | ✅ pieno (pointer, hooks, skills, MCP gbrain/tolaria) | — |
| Copilot CLI (`gh copilot`) | ✅ | ⚠️ gbrain+convergio già nel suo MCP; ma 0 skill roberdan-os (58 di gstack presenti — la pipeline funziona, noi non la usiamo); istruzioni solo nel repo roberdan-os | `~/.copilot/skills/`, AGENTS.md nativo per-repo |
| hermes (Nous) | ✅ (cron, Slack/WhatsApp, serve) | ❌ zero — `platforms/hermes` è uno stub "deferred" ormai smentito dai fatti | Legge AGENTS.md nativamente; ha `mcp`/`skills`/`cron` |
| Warp | ✅ (app) | ❌ zero | AGENTS.md nativo (subdir > root > Global Rules) |
| VS Code Copilot | ✅ | ⚠️ solo repo roberdan-os | `.github/copilot-instructions.md` + fallback CLAUDE.md |
| aider | ✅ | ❌ | CONVENTIONS.md (minore, non in scope) |
| codex / opencode / cursor / gemini | ❌ non installati | n/a | wrapper pronti quando installati |
| ollama | ✅ | n/a — è il motore embedding di gbrain, non un harness agentico | — |

**Gap trasversali:**
- **Nessun pointer globale AGENTS.md**: `~/GitHub/CLAUDE.md` serve solo Claude (traversal). Un tool
  AGENTS.md-nativo aperto in QUALSIASI altro repo sotto `~/GitHub` non riceve nulla del canone.
- **Capture (auto-apprendimento) è Claude-only** (Stop hook). Copilot CLI ha una dir `hooks/` ma il
  formato non è confermato da fonti primarie → NON costruire su formati non verificati
  (self-proposing: documentare `learn/capture.sh` come comando manuale per gli altri tool).
- **Eval harness è claude-only** — contraddice "indipendente dal modello". La ricerca Anthropic
  sulle eval (gen 2026) raccomanda inoltre task derivati da FALLIMENTI REALI (error analysis
  first): ne abbiamo tre documentati (silent-failure, wrong-cwd, leak) non ancora trasformati in
  fixture.
- **evolve/ osserva solo claude/copilot/codex** — mancano hermes e Warp (installati).
- **Nessun gate in validate.sh** che verifichi la copertura di wiring per i tool installati.

**Cosa NON fare (anti-over-engineering, coerente coi giudizi precedenti):** niente wrapper per
tool non installati oltre l'emissione già esistente; niente hook Copilot su formato non
documentato; niente riscrittura della factory per dispatch multi-tool (nessuna evidenza di
bisogno); niente framework eval esterni (promptfoo) finché l'harness interno non è saturato.

## Piano — item eseguibili (modello assegnato, DoD, gate)

Ordine vincolato: P1→P2→P3 toccano `bin/sync.sh` in sequenza (lezione del 2026-07-02: agenti
paralleli sullo stesso checkout collidono su .git/index). P4 e P5 parallelizzabili (file diversi).

| # | Item | Modello | Gate | DoD |
|---|---|---|---|---|
| P1 | **Pointer fabric AGENTS.md**: creare `~/GitHub/AGENTS.md` (thin pointer, speculare al CLAUDE.md esistente); estendere `bin/sync.sh --install` per installare pointer globali per i tool rilevati (`~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`) con skip esplicito se il tool non è installato; override `RDA_*` per testabilità | sonnet | autonomo (additivo, pattern già approvato per CLAUDE.md) | pointer creati per tool presenti; skip pulito per assenti; test isolato; validate green |
| P2 | **Distribuzione Copilot**: `--install` installa le skill roberdan-os in `~/.copilot/skills/` (symlink, collision-skip — stesso pattern del claude-install); check read-only che gbrain sia nel `mcp-config.json` di Copilot con WARN se assente | sonnet | autonomo | skill installate; test isolato con dir fittizia; validate green |
| P3 | **hermes + Warp**: sostituire lo stub `platforms/hermes` con emissione reale (AGENTS.md workspace + istruzioni di setup con comandi esatti, incluso `hermes mcp add` per gbrain, lasciati come comandi documentati = self-proposing); documentare in USAGE che Warp legge AGENTS.md nativamente | sonnet | config `~/.hermes` NON toccata (proposta documentata) | stub sostituito; USAGE aggiornato; validate green |
| P4 | **Eval agent-agnostic + fixture da fallimenti reali**: `RDA_EVAL_AGENT_CMD` (default `claude -p`) in eval/lib.sh; 2 nuove fixture derivate dai fallimenti reali documentati (claim-done-on-exit-0, wrong-cwd); nota sui bias del judge (order permutation già presente — documentarla) | sonnet | autonomo | override provato in stub-test; fixture presenti con checklist; validate green |
| P5 | **evolve/ coverage**: aggiungere hermes-agent releases + Warp changelog ai watch | sonnet | autonomo | URLs aggiunti; run pulito |
| P6 | **Gate tool-coverage in validate.sh**: nuova sezione che, PER I SOLI tool rilevati come installati, asserisce l'artefatto di wiring atteso; no-op silenzioso su clone/CI senza tool | sonnet | autonomo | sezione green in locale; skip pulito simulando assenza |
| P7 | **Review @rex (ecosystem audit) + validazione @thor** dell'intero change-set | opus (rex) + thor | advisory + done-gate | findings gestiti o loggati; thor PASS con evidenza |
| P8 | **Chiusura**: learn capture, handoff, report, push | orchestratore | push = consueto | tutto committato e pushato; report finale |

Card kanban unica per l'iniziativa: `T-tool-independence` (dod = P1..P8 verificati), approvazione
`--by roberto` derivata dal /goal esplicito di questa sessione.

## Esecuzione (completata 2026-07-03)

| Item | Stato | Evidenza |
|---|---|---|
| P1 | done | `~/GitHub/AGENTS.md` creato (pointer thin, speculare al CLAUDE.md); `bin/sync.sh --install` installa pointer globali per tool rilevati: `~/.codex/AGENTS.md` (installato live — il file 0-byte preesistente riempito), `~/.config/opencode/AGENTS.md`, `~/GitHub/AGENTS.md`; `emit_global_agents_pointer()` heredoc deterministico; override `RDA_POINTER_HOME`/`RDA_FORCE_CODEX`/`RDA_FORCE_OPENCODE`; test isolati (install/skip/no-overwrite). Commit `3297656`. |
| P2 | done | `bin/sync.sh`: loop skills-install generalizzato in `install_skills_set()` (era hardcoded solo su `~/.claude/skills`) e riusato per `claude` e `copilot`; install in `~/.copilot/skills/` gated su `~/.copilot` esistente (skip esplicito altrimenti), override `RDA_COPILOT_SKILLS_DIR`; WARN read-only se `mcp-config.json` esiste senza `gbrain` (mai scritto, override `RDA_COPILOT_MCP_CONFIG`). `test/test-sync-install.sh`: 5 sezioni copilot nuove (skip-absent, fresh-install+collision-skip, WARN gbrain mancante, no-WARN gbrain presente) + fix di un bug di isolamento scoperto in corsa (le sezioni pre-esistenti non passavano `RDA_COPILOT_SKILLS_DIR` e cadevano sul default reale `$HOME/.copilot/skills`, scrivendo per davvero sulla macchina durante i test — corretto con `NOCOPILOT_SKILLS_DIR`, verificato before/after count `~/.copilot/skills` invariato). Install reale eseguita: le 8 skill roberdan-os sono symlink verso `platforms/claude/skills/*/SKILL.md` in `~/.copilot/skills/`, nessuna collisione con le 52 skill `gstack-*` (68 totali, prefisso gstack- confermato); `~/.copilot/mcp-config.json` ha già gbrain (nessun WARN). `bash test/test-sync-install.sh` e `bash test/validate.sh` tutti verdi. |
| P3 | done | `bin/sync.sh`: `emit_hermes()` rewritten — `platforms/hermes/README.md` now documents the verified fact (hermes-agent v0.18.0 reads AGENTS.md natively, `--ignore-rules` help text confirms auto-injection) plus self-proposing setup with exact verified commands: `hermes cron create <schedule> "<prompt>" --workdir ~/GitHub` (workdir flag confirmed via `hermes cron create --help` to inject AGENTS.md/CLAUDE.md/.cursorrules and set cwd), `hermes mcp add gbrain --command ~/.gbrain/gbrain-mcp-serve.sh` (exact syntax verified via `hermes mcp add --help` — positional name + `--command`/`--args`, not a `--` passthrough as originally guessed), and skills section reporting the real discovery that `hermes skills` is registry/hub-driven (`tap add <github-repo>`, `install <identifier-or-URL>`) with no local-dir loader found in v0.18.0 — no invented flags. `docs/USAGE.md`: added "Other agentic tools" section (14 lines: Copilot CLI, codex/opencode, Warp, Hermes) — file now 110 lines, under the 150-line cap. `~/.hermes/config.yaml` verified untouched (mtime/hash unchanged after the session). `bash bin/sync.sh --emit-only` regenerated wrappers; `bash test/validate.sh` all green including the determinism drift-check. |
| P4 | done | `RDA_EVAL_AGENT_CMD` in eval/lib.sh (prompt via stdin, mai flag claude-specifici, applicato anche al judge); fixture 11-exit-zero-is-not-done e 12-looks-wired-but-never-ran derivate dai fallimenti reali 2026-07-01/02; README con caveat espliciti sui bias del judge (order-randomization mitiga solo position bias, self-preference stesso-vendor NON mitigato); stub-test dell'override verde. Commit `fff7e65`. |
| P5 | done | `evolve/watch.sh` +hermes-agent (github.com/NousResearch/hermes-agent/releases) +warp (docs.warp.dev/getting-started/changelog); URL verificate 200 con curl; run isolato (`RDA_EVOLVE_STATE` custom) su 5 fonti pulito, `shellcheck evolve/watch.sh` pulito; test/validate.sh: FAIL preesistente in bin/sync.sh (SC2088, altro agente P1 in corso) confermato non causato da questo item via stash/pop |
| P6 | done | `test/validate.sh`: nuova sezione finale "tool coverage (installed tools only)" — per ciascun tool rilevato presente (`~/.claude`, `~/.copilot`, `~/.codex`, `command -v opencode`, `~/GitHub`) asserisce l'artefatto di wiring reale: 3 skill claude non-collidenti (`auto-checkpoint`/`sync`/`verify-done`, `review`/`ship` esplicitamente esclusi perché collidono con gstack per scelta documentata), 8 skill copilot + gbrain in `mcp-config.json`, `~/.codex/AGENTS.md` non vuoto, `~/.config/opencode/AGENTS.md`, `~/GitHub/AGENTS.md` che menziona roberdan-os. Assert fallito → FAIL + remediation (`bash bin/sync.sh --install`); tool assente → riga `skip:`, mai FAIL. Verificato in locale: `bash test/validate.sh` ALL GREEN con 15 righe `ok` nella nuova sezione che riflettono il wiring reale della macchina (3 claude + 8 copilot + mcp-config + codex + \$HOME/GitHub; opencode skip perché non installato). Simulato CI con `HOME=$(mktemp -d) bash test/validate.sh`: ALL GREEN, sezione tutta `skip:` tranne una riga — side-effect pre-esistente e non causato da questo item: `test/test-sync-install.sh` (riga 40, non toccato da P6) invoca `bin/sync.sh --install` senza `RDA_POINTER_HOME`, quindi con `$HOME` sovrascritta scrive per davvero `$HOME/GitHub/AGENTS.md` prima che la sezione 10 giri, che poi la trova e riporta correttamente `ok` invece di `skip` — nessun FAIL, comportamento onesto rispetto allo stato reale del filesystem in quel momento. Isolato e riconfermato: la sola sezione 10 estratta ed eseguita su un `HOME` mai toccato da altre sezioni produce 5 righe `skip:` e zero FAIL — no-op totale come richiesto. `shellcheck -S warning test/validate.sh` pulito (fix di un SC2088 tilde-in-quotes). Nessun tocco a `bin/sync.sh`/`eval/`/`evolve/`; nessun commit creato (per istruzione). |
| P7 | done | @rex (opus) review dell'intero change-set: **APPROVE**, 0 CRITICAL/HIGH, ogni claim sui tool esterni spot-checked contro la macchina reale; findings LOW-1/2/3+INFO-4 rimediati (commit `2c61459` — ~GitHub mai creato come side-effect, detection opencode simmetrica installer/gate che ha subito scovato il pointer mancante e l'ha fatto installare, coverage ownership-aware via readlink), INFO-5/6 deliberatamente solo annotati. @thor: **PASS** con evidenza live (39 ok in validate, spot-check readlink/pointer reali, remediation verificata genuina). |
| P8 | done | Card `T-tool-independence` chiusa con evidenza thor (`kb finish`); learning catturato nel meta-loop inbox; handoff aggiornato; 10+ commit pushati su main. |
