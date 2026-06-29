# Loop Protocol — contratto standard del loop autonomo

> Incluso (per riferimento) in ogni `AGENTS.md` loop-aware. Definisce come un agente
> opera in **loop autonomo** allineato al modo di lavorare di Roberto: autonomia totale
> + evidence-first + verifica empirica. **Affidabile senza daemon**: lo stato è durevole
> su file, il resume è idempotente, le terminal-condition sono verificate su ground truth.

---

## Il contratto

```
state:              <state.db strutturato> + .agent-state/<task>.jsonl (cursor)
terminal-condition: <check empirico job-specific — es. "cargo test green + CI #N pass">
checkpoint:         1 commit per fase, messaggio evidence-first (SHA/PR/CI in ogni update)
escalation:         2 tentativi falliti sullo stesso problema → opus, logga il motivo
sync-on-iteration:  post-task-sync (vault + cvg + repo) a fine di OGNI fase
resume:             leggi lo stato all'avvio, riparti dall'ultimo step done, mai rifare
stuck:              2 pass senza progresso → STOP, segnala cosa è wedged, non loopare
```

## Componenti

### 1. Stato durevole (daemon-optional)
- **State store:** SQLite a path noto — `~/.convergio/v3/state.db` se presente, altrimenti
  `~/.roberdan-os/state.db`. Timestamp RFC3339.
- **Cursor per task:** `.agent-state/<task>.jsonl` (append-only) — un record per step con
  esito ed evidenza. `.agent-state/` è gitignored.
- Leggibile sia dagli hook sia da Convergio se attivo. **Il loop non dipende dal daemon:**
  Convergio è osservatore opzionale che *legge* lo stesso state file, mai single point of failure.

### 2. Terminal-condition (verifica empirica)
Mai "dovrebbe funzionare". La condizione di fine è un check su **ground truth**:
`cargo test` verde, `gh run` SUCCESS, file esistente su disco, `0 unembedded chunks`.
La verifica la fa `thor` (vedi `agents/thor.md`) o un check job-specific.

### 3. Resume idempotente
All'avvio: leggi `state.db` + il cursor jsonl, identifica l'ultimo step `done`, **riparti da lì**.
Un task ben costruito legge lo stato persistito e continua — un task killed/stallato si
**rilancia, non si rifà da capo**.

### 4. Escalation
2 tentativi falliti sullo stesso problema → scala il modello (Opus per analisi critica) e
**logga il motivo** nel cursor. Se 2 pass consecutivi non fanno progresso, è genuinamente
bloccato: STOP, segnala cosa è wedged (riga oversize, chiave mancante, lock), non loopare.

### 5. Segnalazione proattiva (anti-polling)
Ogni checkpoint è un update **evidence-first**:
`[fase 3/7 ✓] commit a1b2c3d · CI #4821 green · next: applica migration`
Mai "sto lavorando". Roberto si fida degli artefatti, non delle parole.

---

## Per-platform driver

| Platform | Driver |
|---|---|
| **Claude Code** | `/loop` + `ScheduleWakeup` per attese esterne (CI/deploy/embed): `submit → wakeup +Nmin → check terminal-condition → done \| re-arm`. |
| **Altri (Copilot/Codex)** | `launchd`/`cron` leggono lo stesso checkpoint file e rilanciano fino alla terminal-condition. |

Il kit iniettabile che implementa questo contratto in una sessione qualsiasi è
[`skills/auto-checkpoint`](../skills/auto-checkpoint/skill.md).

---

## Gate umani

Il loop **non automatizza mai** i [gate umani](../AGENTS.md#gate-umani). In particolare:
merge su `main` con impatto su protezioni/security/release, force-push, spesa/email
esterne, cancellazioni irreversibili, decisioni strategiche. Questi passano sempre da
Roberto con un messaggio diretto — mai il relay di un coordinator.
