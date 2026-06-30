# learn-protocol — apprendimento continuo (capture → distill → quarantena)

Distilla cosa è cambiato nel modello del mondo, dopo le interazioni, in memoria
classificata. **Capture ≠ distill** (disaccoppiati per portabilità + anti-rumore).
Vedi [[ADR-0001]], [[memory-protocol]].

## 1. Capture (per-platform, economico)

Ogni platform appende a un cursor durevole, **senza giudizio**:
```
~/.roberdan-os/learnings/inbox/<YYYY-MM-DD>-<session>.md   # 1 record/segnale
```
Claude: hook `Stop` opt-in (`RDA_LEARN=1`). Altri: comando esplicito / fine-task.
Nessun lock, nessuna scrittura nel vault qui.

## 2. Distill (batch periodico, launchd)

`learn/distill.sh` → legge l'inbox accumulato → per ogni segnale:
1. **Classifica** nella tassonomia (5 classi) + scarta l'effimero (contesto della singola
   issue ≠ lezione riusabile).
2. **Dedup-before-write:** `gbrain search` sulla source `vault` → se match, propone
   **merge/supersedes**, non un file nuovo.
3. **Privacy filter** (deny-list come codice) → redact o drop.
4. Scrive **candidati in quarantena** `~/.roberdan-os/learnings/quarantine/`, mai nel vault diretto.

## 3. Gate (promozione)

- `tool-quirk` (≥2×) e `correction` (con citazione) → auto-eligibili alla promozione.
- `capability-gap`, `voice`, `decision` ambigui → **conferma umana** prima di promuovere.
- La promozione vera nel vault la fa il job single-writer di [[ontology-protocol]].

## Anti-degradazione

Mai auto-scrittura cieca nel canone. Un learning mal interpretato che diventa "verità"
si auto-rinforza: per questo **quarantena + corroborazione**, non commit diretto.
