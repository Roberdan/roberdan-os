#!/usr/bin/env bash
# validate.sh — roberdan-os CI gate. Runs on every PR.
# 1) frontmatter lint (agents vs skills: distinct schemas)  2) link check (exempts [[wikilink]])
# 3) drift check (generation is deterministic)  4) shellcheck  5) leak check  8) sync.sh --install
# skills symlink step (isolated, incl. emit-only must NOT touch it)  10) tool coverage — for
# tools DETECTED as installed on THIS machine, asserts the real wiring artifact still exists
# (skip, never FAIL, for tools not installed — must be a total no-op on a clean CI box)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()      { printf "  ok: %s\n" "$1"; }

# Il motore (lancio parallelo + raccolta ordinata) vive in test/lib-suites.sh.
# shellcheck source=test/lib-suites.sh
. "$ROOT/test/lib-suites.sh"

for _s in test-canon-guardrails test-factory-kb test-kb-views test-kb-board test-kb-done-gate test-kb-diet test-kb-queue \
          test-file-size-ratchet test-edge-only test-kb-precheck \
          test-kb-root-resolution test-kb-start-worktree-cause test-nested-board-notice \
          test-federated-kb test-leak-check test-directory-dump-check test-private-marker test-new-area-check test-fork-merge test-autofmt \
          test-receipts test-install-hooks test-pending test-metaloop \
          test-evolve-declined test-evolve-watch test-review-budget test-bus test-bus-mcp \
          test-bus-doorbell test-bash-guard test-validate-wiring test-evolve-sources test-kb-autothor \
          test-kb-autothor-board test-kb-autothor-dir test-kb-repo-path-agree \
          test-goal-gate test-gh-shim test-bus-lock test-thor-verdict test-install-git-hooks test-install-hooks-dedup \
          test-tool-coverage test-frontmatter test-precommit-hook test-canon-structure \
          test-drift test-links test-privacy test-plan-coverage; do
  _spawn "$_s"
done
unset _s
_spawn_serial_group test-sync-install test-copilot-adapter test-skill-name-collision

# --- 1) Frontmatter lint (agenti, skill, card, schema federato) ---------------
# Le quattro famiglie vivono in test/test-frontmatter.sh: il frontmatter e' il contratto fra un
# file e chi lo carica, e un contratto rotto non fallisce rumorosamente — viene caricato lo
# stesso. La suite stampa le sue quattro sezioni, che sono quelle che si leggevano qui.
if _suite test-frontmatter; then _suite_out test-frontmatter | grep -vE '^test-frontmatter:'; else _suite_out test-frontmatter; err "test-frontmatter — see bash test/test-frontmatter.sh"; fi
# --- i cancelli umani sono numerati senza buchi e ogni puntatore ne dichiara il numero giusto -> test/test-canon-structure.sh
if _suite test-canon-structure; then _suite_out test-canon-structure | grep -vE '^test-canon-structure:'; else _suite_out test-canon-structure; err "test-canon-structure — see bash test/test-canon-structure.sh"; fi
section "canon guardrails"; if _suite test-canon-guardrails; then ok "cross-tool guardrails present"; else _suite_out test-canon-guardrails; err "test-canon-guardrails failed"; fi
# --- i link markdown relativi puntano a qualcosa che esiste -> test/test-links.sh
if _suite test-links; then _suite_out test-links | grep -vE '^test-links:'; else _suite_out test-links; err "test-links — see bash test/test-links.sh"; fi
# --- la generazione di bin/sync.sh e deterministica -> test/test-drift.sh
if _suite test-drift; then _suite_out test-drift | grep -vE '^test-drift:'; else _suite_out test-drift; err "test-drift — see bash test/test-drift.sh"; fi
# --- 4) Shellcheck -----------------------------------------------------------
section "shellcheck (hooks + bin + test + eval + factory + dispatcher shims + lint-cards + bus)"
# factory/*.sh, the runner-shims and kanban/lint-cards.sh are security-sensitive (dispatcher
# sandbox path) — kept in the gate, not just hand-checked (rex nit #1). kanban/kb.sh is
# deliberately NOT globbed: it carries pre-existing SC1010/SC2010 warnings in untouched code.
SHELLCHECK_TARGETS=(hooks/*.sh bin/*.sh test/*.sh eval/*.sh factory/*.sh factory/runner-shims/* kanban/lint-cards.sh kanban/dash.sh kanban/worktree.sh learn/*.sh ontology/*.sh bus/*.sh)
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "${SHELLCHECK_TARGETS[@]}"; then ok "shellcheck clean"; else err "shellcheck warning/error"; fi
else
  printf "  skip: shellcheck not installed\n"
  for f in "${SHELLCHECK_TARGETS[@]}"; do bash -n "$f" || err "syntax: $f"; done
fi
# --- nessun termine riservato nel canone pubblico -> test/test-privacy.sh
if _suite test-privacy; then _suite_out test-privacy | grep -vE '^test-privacy:'; else _suite_out test-privacy; err "test-privacy — see bash test/test-privacy.sh"; fi
# --- 6) Factory + kb gates (real assertions, not a smoke test) ---------------
section "factory + kb gates"
if _suite test-factory-kb; then ok "kb gates + factory guardrails green"; else err "test-factory-kb — see bash test/test-factory-kb.sh"; fi

# --- 6b) kb detail/ops views (history/archive/plans/plan/sched) --------------
section "kb views (history/archive/plans/plan/sched)"
if _suite test-kb-views; then ok "kb views green"; else err "test-kb-views — see bash test/test-kb-views.sh"; fi
if _suite test-kb-board; then ok "board rendering green (one readable line per card)"; else err "test-kb-board — see bash test/test-kb-board.sh"; fi

# --- 6b3) $ROOT must survive the symlink it is always reached through ---------
# `kb` is installed as ~/.local/bin/kb -> kanban/kb.sh, and BASH_SOURCE reports
# the LINK. The naive derivation therefore resolved ~/.local on every PATH
# invocation: `kb lint` looked for a script that was not there, RDA_LEAKCHECK
# pointed at a privacy check that was not there, and the fallback board became
# ~/.local/kanban — created by mkdir -p, so 32 real cards accumulated on a board
# no view aggregated. One loud symptom, three silent ones.
section "kb \$ROOT resolution (symlinked install)"
if _suite test-kb-root-resolution; then ok "\$ROOT survives symlinks; no phantom board"; else err "test-kb-root-resolution — see bash test/test-kb-root-resolution.sh"; fi
if _suite test-kb-start-worktree-cause; then ok "kb start names the real worktree failure, never a false one"; else err "test-kb-start-worktree-cause — see bash test/test-kb-start-worktree-cause.sh"; fi

# --- 6b4) kb done-gate must be mechanical, not honor-system -------------------
# Pins both directions: forged evidence (rubber-stamps, fake SHAs) is refused, and
# real evidence (resolvable SHA, test output, existing path) still passes. The gate
# that only refuses is as useless as the one that only accepts.
section "kb done-gate (mechanical evidence, no rubber-stamps)"
if _suite test-kb-done-gate; then ok "done-gate refuses forged evidence, accepts real"; else err "test-kb-done-gate — see bash test/test-kb-done-gate.sh"; fi

# I tre freni al board (regole 1/4/5 del 2026-07-30). Qui, e non solo nel file di test,
# perche' un test che nessuno lancia e' codice morto che sembra un gate.
section "kanban — i freni al board che cresce (una card in corso per repo, una condizione, un progetto alla volta)"
if _suite test-kb-diet; then ok "i tre freni rifiutano il caso cattivo E lasciano passare quello legittimo"; else err "test-kb-diet — see bash test/test-kb-diet.sh"; fi

# La coda autorizzata sposta il gate umano da "quale card" a "quale lista". La proprieta' che
# lo rende uno SPOSTAMENTO e non una RIMOZIONE e' una sola — cio' che nasce dopo lo scatto non
# parte — ed e' asserita li' dentro.
section "kanban — coda autorizzata (Roberto approva la lista, non le card una per una)"
if _suite test-kb-queue; then ok "la coda cammina da sola E si ferma su cio' che e' nato dopo"; else err "test-kb-queue — see bash test/test-kb-queue.sh"; fi

# Le tre domande da fare a una card PRIMA di eseguirla. La direzione che conta di piu' e' il
# SILENZIO: un avviso che compare sempre e' rumore, e il giorno che dice il vero nessuno lo legge.
section "kanban — precheck (e' ancora valida? la fa gia' un'altra? e' gia' stata fatta?)"
if _suite test-kb-precheck; then ok "avvisa sui tre casi E tace su una card pulita"; else err "test-kb-precheck:"; _suite_out test-kb-precheck | sed 's/^/    /'; fi

section "dimensione dei file — ratchet a 300 righe (i vecchi passano, i nuovi no)"
if _suite test-file-size-ratchet; then ok "nessun file nuovo nasce oltre 300 righe, nessun file baselinato cresce"; else err "test-file-size-ratchet — see bash test/test-file-size-ratchet.sh"; fi

# Limite dichiarato: oggi qui non c'e' codice Playwright, quindi questo gate impedisce che il
# primo che entrera' nasca su Chrome. PASS = "nessuno ha violato", non "abbiamo visto Edge".
section "browser — Playwright parla con Edge, e se manca si ferma"
if _suite test-edge-only; then ok "nessun codice avvia Chrome/Chromium; il canone impone il blocco e prevede l'eccezione"; else err "test-edge-only:"; _suite_out test-edge-only | sed 's/^/    /'; fi

# --- 6c) federated kanban + dormant dispatcher --------------------------------
section "federated kanban (cwd-scoping, kb all/handoff, init, locks, dormant dispatcher)"
# On failure, surface the test's own output (indented) instead of hiding it behind a "see …"
# pointer — a failing gate must show the evidence, especially for CI-only failures.
_suite test-federated-kb; _fedkb_out="$(_suite_out test-federated-kb)"
if [ $? -eq 0 ]; then ok "federated kb + dispatcher gates green"; else
  printf '%s\n' "$_fedkb_out" | grep -iE '===|ok:|err|FAIL|got:|outside=|inside=|rc=' | sed 's/^/    /'
  err "test-federated-kb failed (output above)"
fi

# --- 6d) dispatcher WIRED even while dormant (@rex #5) ------------------------
# A module that exists but has no live entry-path is not "wired" — dormancy must
# come from REFUSAL (preflight #5/#8), not from being unreachable. This check FAILS
# if `kb dispatch` no longer routes to an executable dispatch-runner.sh.
section "dispatcher wired (kb dispatch -> factory/dispatch-runner.sh) even while dormant"
if grep -qE '^[[:space:]]*dispatch\)[^#]*factory/dispatch-runner\.sh' kanban/kb.sh && [ -x factory/dispatch-runner.sh ]; then
  ok "kb dispatch routes to an executable dispatch-runner.sh (dormant by refusal, not unreachable)"
else
  err "kb dispatch is NOT wired to factory/dispatch-runner.sh — dormant-by-unreachable is forbidden (@rex #5)"
fi

# --- 7) I quattro cancelli di privacy -> test/validate-privacy.sh (sourced: usa section/ok/err)
# shellcheck source=test/validate-privacy.sh
. "$ROOT/test/validate-privacy.sh"
# --- il hook pre-commit e installato E aggiornato -> test/test-precommit-hook.sh
if _suite test-precommit-hook; then _suite_out test-precommit-hook | grep -vE '^test-precommit-hook:'; else _suite_out test-precommit-hook; err "test-precommit-hook — see bash test/test-precommit-hook.sh"; fi
section "board annidata — un commit che non include le card lo dice"
if _suite test-nested-board-notice; then ok "kanban/ sporca -> il commit avvisa, e passa comunque"; else err "test-nested-board-notice — see bash test/test-nested-board-notice.sh"; fi

# --- 7b) fork merge-clean proof (the v2.0.0 engine/identity split guarantee) ----------
section "fork merge-clean — identity-only fork merges upstream engine edits, zero conflicts"
if _suite test-fork-merge; then ok "merge-clean proof green (see bash test/test-fork-merge.sh)"; else err "test-fork-merge — see bash test/test-fork-merge.sh"; fi

# --- 8) sync.sh --install: skills symlink step (isolated, no real ~/.claude touched) ---
section "sync.sh --install — skills symlink step (isolated via RDA_CLAUDE_SKILLS_DIR)"
if _suite test-sync-install; then ok "install symlink/skip logic verified (see bash test/test-sync-install.sh)"; else err "test-sync-install — see bash test/test-sync-install.sh"; fi
if _suite test-skill-name-collision; then ok "skill-name collision: rdos- namespace, retire, heal (see bash test/test-skill-name-collision.sh)"; else err "test-skill-name-collision — see bash test/test-skill-name-collision.sh"; fi

# --- 8a) Copilot native adapter (agents + extension emission/install/load/guards) ---
section "copilot native adapter — emission, collision-safe install, extension load + guard mapping"
if _suite test-copilot-adapter; then ok "copilot adapter verified (see bash test/test-copilot-adapter.sh)"; else err "test-copilot-adapter — see bash test/test-copilot-adapter.sh"; fi

# --- 8b) hooks/autofmt.sh input contract (stdin JSON; the old env-var API was a silent no-op) ---
section "autofmt hook — stdin JSON input contract"
if _suite test-autofmt; then ok "autofmt receives files via stdin JSON (see bash test/test-autofmt.sh)"; else err "test-autofmt — see bash test/test-autofmt.sh"; fi

# --- 8b2) bash-guard decisions. Until 2026-07-31 the guard blocking force-push, `reset --hard`
# and source-in-a-docs-commit had NO test: each scar could have returned with the suite green.
section "bash guard — deny/ask/allow decisions per rule"
if _suite test-bash-guard; then ok "invisible-character prefilter, force-push, reset/clean and docs-staging rules all fire, and the allow cases are not over-blocked"; else _suite_out test-bash-guard; err "test-bash-guard — see bash test/test-bash-guard.sh"; fi

# --- 8b3) goal-gate: l'unico hook che BLOCCA. Meta' delle asserzioni verificano che LASCI
# PASSARE — un cancello che non si apre piu' e' peggio di uno che non si chiude mai.
section "goal-gate — un turno non si chiude con la coda autorizzata ancora piena"
if _suite test-goal-gate; then ok "blocca finche' restano card autorizzate, e molla su coda finita, nessuna coda, interruttore, stallo e tetto"; else _suite_out test-goal-gate; err "test-goal-gate — see bash test/test-goal-gate.sh"; fi

# --- 8b4) gh-shim: l'account GitHub si sceglie dal repo, non da uno stato globale conteso.
# La maggioranza delle asserzioni verifica che FALLISCA APERTO: uno shim su un comando usato
# cento volte al giorno non puo' essere l'anello che si spezza.
section "gh-shim — l'account si sceglie dal repo, e nei casi ignoti non tocca niente"
if _suite test-gh-shim; then ok "sceglie la cartella dal remote, il -R vince sul cwd, gli argomenti passano interi, e in ogni caso ignoto lancia il gh vero invariato"; else _suite_out test-gh-shim; err "test-gh-shim — see bash test/test-gh-shim.sh"; fi

# --- 8b5) il lucchetto delle suite bus: un orfano si riusa, un vivo si rispetta. Due volte in
# un giorno un lucchetto non rilasciato ha fatto uscire ROSSO un test innocente.
section "lucchetto bus — un orfano si riusa, un proprietario vivo si rispetta"
if _suite test-bus-lock; then ok "riusa il lucchetto di un processo morto, rifiuta quello di uno vivo, e aspetta prima di dichiarare orfano un lucchetto senza PID"; else _suite_out test-bus-lock; err "test-bus-lock — see bash test/test-bus-lock.sh"; fi

# --- 8b6) come si legge il verdetto di @thor. Due volte in un giorno il gate ha rifiutato una
# verifica RIUSCITA, e tutte e due le volte rilanciare identico e' bastato: la lezione peggiore.
section "verdetto di @thor — tollerante sulla forma, inflessibile sul contenuto"
if _suite test-thor-verdict; then ok "legge il verdetto anche in grassetto o con altri separatori, non ne inventa dove non c'e', e dice diverso un turno finito senza verdetto da un processo morto"; else _suite_out test-thor-verdict; err "test-thor-verdict — see bash test/test-thor-verdict.sh"; fi

# --- 8b7) il controllo git installato deve sopravvivere alla cartella da cui lo si installa.
# Il canone impone un worktree per card: incidere quel percorso = bloccare ogni commit dopo.
section "install-git-hooks — incide il checkout principale, non il worktree che sparira"
if _suite test-install-git-hooks; then ok "dal worktree incide il principale, il commit regge dopo la rimozione, il salto resta condizionato e fuori da un repo non esplode"; else _suite_out test-install-git-hooks; err "test-install-git-hooks — see bash test/test-install-git-hooks.sh"; fi

# --- 8b8) install-hooks dichiara di essere idempotente: deve esserlo anche quando la stessa
# cosa e' scritta in due modi. Raddoppiare i controlli e' peggio che non installarli.
section "install-hooks — due scritture dello stesso comando sono lo stesso comando"
if _suite test-install-hooks-dedup; then ok "riconosce \$HOME, la tilde e il bash iniziale come la stessa cosa, e NON appiattisce redirezioni, argomenti o script diversi"; else _suite_out test-install-hooks-dedup; err "test-install-hooks-dedup — see bash test/test-install-hooks-dedup.sh"; fi

# --- 8c) loop receipts emitter (schema, append-only, opt-in placement, no pollution) ---
section "loop receipts — loop/receipt.sh emitter contract"
if _suite test-receipts; then ok "receipt emitter green (see bash test/test-receipts.sh)"; else err "test-receipts — see bash test/test-receipts.sh"; fi

# --- 8d) install-hooks: settings.json merge is additive/idempotent/non-destructive ---
section "install-hooks — settings.json merge contract"
if _suite test-install-hooks; then ok "install-hooks merge green (see bash test/test-install-hooks.sh)"; else err "test-install-hooks — see bash test/test-install-hooks.sh"; fi

# --- 8e) approval inbox: kb pending aggregates + counts, digest writes without failing ---
section "approval inbox — kb pending + digest contract"
if _suite test-pending; then ok "approval inbox green (see bash test/test-pending.sh)"; else err "test-pending — see bash test/test-pending.sh"; fi

# --- 8e) meta-loop wired end-to-end (capture -> distill[real class] -> curate promotes) ---
# The self-improving loop must actually PROMOTE an approved learning, not stall at
# `class: TODO`. Proves capture->distill(real class)->human-approve->curate-promotes,
# plus the two honesty gates (ephemera dropped, unapproved never promoted).
section "meta-loop — capture -> distill -> curate promotion (test/test-metaloop.sh)"
if _suite test-metaloop; then ok "meta-loop promotes end-to-end (see bash test/test-metaloop.sh)"; else err "test-metaloop — see bash test/test-metaloop.sh"; fi

# --- 8b) evolve rejected-proposal buffer --------------------------------------
# Pins that a reworded repeat is recognized, a genuine novelty is NOT suppressed, and the
# buffer actually reaches the agent through the card watch.sh writes (wired, not just present).
section "evolve rejected-proposal buffer (test/test-evolve-declined.sh)"
if _suite test-evolve-declined; then ok "declined buffer matches rewordings, spares novelties, reaches the card"; else err "test-evolve-declined — see bash test/test-evolve-declined.sh"; fi

section "kb autothor — @thor verifica da solo, e uno SKIP non diventa un PASS"
if _suite test-kb-autothor; then ok "PASS chiude e scrive l'evidenza di thor, FAIL e SKIP lasciano la card in doing, --by non convoca thor"; else _suite_out test-kb-autothor; err "test-kb-autothor — il cancello doing->done non si comporta come dichiarato"; fi

section "kb autothor — la card viene cercata sul board dove vive, anche in un repo federato"
if _suite test-kb-autothor-board; then ok "una card di un repo federato viene trovata da @thor, e togliere RDA_KANBAN dalla chiamata la rende di nuovo introvabile"; else _suite_out test-kb-autothor-board; err "test-kb-autothor-board — @thor cerca la card sul board sbagliato: per i repo federati il cancello rifiuta per indirizzo, non per merito"; fi
if _suite test-kb-autothor-dir; then ok "@thor guarda il checkout del repo che la card nomina, e rimettere il fallback a \$ROOT lo rimanda nel checkout sbagliato"; else _suite_out test-kb-autothor-dir; err "test-kb-autothor-dir — @thor verifica una card contro una cartella dedotta: il cancello APPROVA per indirizzo, su codice che non c'entra"; fi
if _suite test-kb-repo-path-agree; then ok "le copie di _repo_path rispondono identico (nome vuoto compreso: prima due davano \$HOME/GitHub/)"; else _suite_out test-kb-repo-path-agree; err "test-kb-repo-path-agree — due implementazioni della stessa risoluzione divergono: una risponde una cartella che l'altra rifiuta"; fi

section "evolve sources — le fonti sorvegliate sono leggibili via curl, non solo raggiungibili"
if _suite test-evolve-sources; then ok "$(_suite_out test-evolve-sources | grep -cE "^  (ok|SKIP)") fonti controllate (SKIP dichiarato se manca la rete)"; else _suite_out test-evolve-sources; err "test-evolve-sources — una fonte apre card che nessun agente puo' leggere"; fi

section "evolve watcher backpressure (test/test-evolve-watch.sh)"
if _suite test-evolve-watch; then ok "a changelog change while a card is still open refreshes it instead of adding a sibling, and the watcher never moves a card between columns"; else _suite_out test-evolve-watch; err "test-evolve-watch — see bash test/test-evolve-watch.sh"; fi

# Messages between agents, never execution. The load-bearing checks are the negative
# ones: the bus must not be able to start an agent (that is factory/dispatch-runner.sh,
# dormant by a reviewed decision), write kanban state, or carry acceptance criteria.
# An unwired test is an unverified claim, so it runs here — see bus/bus-protocol.md.
section "review budget — a review loop that cannot run forever (test/test-review-budget.sh)"
if _suite test-review-budget; then ok "a spent review budget exits 3 and demands a human decision instead of another round"; else err "test-review-budget — see bash test/test-review-budget.sh"; fi

section "agent bus — messages, never execution (test/test-bus.sh)"
if _suite test-bus; then ok "bus delivers durably, attributes, resolves citations to no more than they prove, and executes nothing"; else _suite_out test-bus; err "test-bus — see bash test/test-bus.sh"; fi

section "agent bus — the doorbell rings, it never delivers (test/test-bus-doorbell.sh)"
if _suite test-bus-doorbell; then ok "the PostToolUse doorbell announces a COUNT in the one dialect the model hears, leaks no body, consumes no mail, is silent at zero, and is wired nowhere that can continue a turn"; else _suite_out test-bus-doorbell; err "test-bus-doorbell — see bash test/test-bus-doorbell.sh"; fi

section "agent bus — the typed MCP surface (test/test-bus-mcp.sh)"
if _suite test-bus-mcp; then ok "the MCP surface dispatches send/read/log only, refuses unknown tools, and stores shell metacharacters as inert data"; else _suite_out test-bus-mcp; err "test-bus-mcp — see bash test/test-bus-mcp.sh"; fi
# THE MUTATION HARNESS IS NO LONGER A GATE. `bash test/test-bus-mutants.sh` is
# still in the tree and still useful to run by hand when the bus changes shape,
# but it does not decide whether this repo is releasable, for three reasons that
# were measured on 2026-07-28 rather than argued:
#
#   - IT WAS NEVER GREEN. Its floors swept ~/.claude, whose directory mtime moves
#     whenever any live agent session writes. On this machine one always is, so
#     the gate accused the session running it. Not once did a green run exist.
#   - IT COST 60 MINUTES FOR THE WRONG REASON. 96.9 of the suite's 188 seconds
#     were an awk pass handed 9MB of xtrace including a 60,019-character line;
#     27 of the 62 mutants reach that check, so ~45 of the 60 minutes were one
#     badly-fed pipeline, not 62 justified proofs.
#   - IT DECLARES ITS OWN INSUFFICIENCY. `survives brace-blind` is an asserted
#     SURVIVOR: it starts an agent inside a stderr-redirected compound command
#     and this suite stays green. Its comment says there is no in-process fix.
#
# A gate that cannot pass, costs an hour, and states in writing that it cannot
# enforce its own central property is not a gate. Property 1 ("never starts an
# agent") is now enforced by the SHAPE of the bus core rather than detected
# afterwards; property 2 ("never writes kanban state") is still checked, in
# process, by test-bus.sh above.

# --- 9) eval/ harness (stub-mode pipeline test) -------------------------------
# eval/ measures whether the behavioral canon changes agent output (see eval/README.md). The
# actual with/without-canon comparison needs a real `claude` binary and Roberto's own machine —
# what CI can verify is that the harness itself (run-eval.sh -> judge.sh -> report.sh) is
# mechanically correct, resumable, and blind — see eval/test-eval-pipeline.sh.
section "eval/ harness — stub-mode pipeline (run-eval -> judge -> report)"
if bash eval/test-eval-pipeline.sh >/dev/null 2>&1; then ok "eval harness verified (see bash eval/test-eval-pipeline.sh)"; else err "test-eval-pipeline — see bash eval/test-eval-pipeline.sh"; fi

# --- 10) tool coverage (installed tools only) --------------------------------
# Wiring can silently rot: Roberto reinstalls Copilot, deletes a pointer, upgrades
# codex — nothing notices ("looks wired but never ran", see eval/tasks/12). For
# each tool DETECTED as present on this machine, assert its wiring artifact still
# exists. A tool that isn't installed is a clean "skip", never a FAIL — so this
# section is a total no-op on a fresh clone / CI box with no tools installed.
section "tool coverage (installed tools only)"
if _suite test-tool-coverage; then _suite_out test-tool-coverage | grep -vE '^test-tool-coverage:'; else _suite_out test-tool-coverage; err "test-tool-coverage — see bash test/test-tool-coverage.sh"; fi
# --- ogni clausola normativa del piano ha una card o una decisione scritta -> test/test-plan-coverage.sh
if _suite test-plan-coverage; then _suite_out test-plan-coverage | grep -vE '^test-plan-coverage:'; else _suite_out test-plan-coverage; err "test-plan-coverage — see bash test/test-plan-coverage.sh"; fi
# --- Result --------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "validate: ✅ ALL GREEN"; exit 0; else echo "validate: ❌ FAIL (see above)"; exit 1; fi
