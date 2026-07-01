---
name: premortem
description: "Premortem su un piano/lancio/prodotto/assunzione/strategia/decisione. Assume che sia GIÀ fallito tra 6 mesi e lavora a ritroso per trovare ogni causa. Produce un piano rivisto con i blind-spot esposti. TRIGGER OBBLIGATORI: 'premortem this/questo', 'cosa può ucciderlo', 'stress-test questo piano', 'cosa mi sto perdendo', 'trova i blind spot'. TRIGGER FORTI: 'cosa può andare storto', 'buca questo piano', 'dove si rompe', 'fai l'avvocato del diavolo'. NON attivare su feedback semplici, domande fattuali. SÌ quando c'è un piano/impegno dove sbagliare costa caro."
providers: [claude, copilot, codex]
---

# premortem

L'opposto del postmortem: invece di capire cosa è andato storto dopo il fallimento,
**immagini che sia già fallito** e capisci perché, prima di partire. Metodo di Gary Klein
(HBR); Kahneman lo chiamava la sua tecnica decisionale più preziosa. Meccanismo:
"questo è morto, spiega come" → il cervello genera cause specifiche e oneste, mentre
"è un buon piano?" → risposte compiacenti. **Rompe il default accomodante degli LLM.**

## Quando (e quando no)

**Sì:** prodotto/feature da costruire, lancio con soldi/reputazione, cambio pricing/modello,
assunzione, pivot di posizionamento, partnership/deal, ogni impegno dove sbagliare costa caro.
**No:** idee vaghe senza piano (prima aiuta a pianificare), domande con una risposta,
feedback su una bozza (è editing), decisioni già prese e irreversibili (il premortem serve
solo se puoi ancora cambiare rotta).

## Soglia minima di contesto (obbligatoria)

Un premortem vale quanto il contesto. Prima di lanciarlo servono 3 cose — cercale prima nel
contesto (conversazione, `AGENTS.md`, memoria/vault, file citati), poi chiedi solo il pezzo
mancante più importante, **una domanda alla volta**:
1. **Cos'è?** (descrivibile in una frase)
2. **Per chi / chi impatta?** (i fallimenti dipendono da chi è coinvolto)
3. **Cosa significa successo?** (il fallimento è il successo invertito)

## Sessione

1. **Frame esplicito:** *"È fra 6 mesi. [Il piano] è fallito. È finito. Guardiamo indietro
   e capiamo cosa è andato storto."* — è il meccanismo psicologico, non saltarlo.
2. **Raw premortem:** genera **ogni** ragione genuina per cui è morto — specifica, ancorata
   ai dettagli reali, minaccia vera (non edge-case). Quante sono reali: 4 o 9, non padding.
3. **Deep-dive paralleli:** **un agente per ragione, tutti in parallelo** (Agent tool, un solo
   messaggio con più tool-use). Ogni agente riceve il contesto pieno + la sua ragione e produce:
   (a) **storia del fallimento** (2-3 paragrafi, come un caso reale), (b) **assunzione sottostante**
   (1 frase), (c) **early-warning** (1-2 segnali osservabili/misurabili). <300 parole, niente hedge.
4. **Sintesi (è il prodotto):**
   - **Fallimento più probabile** (su cui concentrarsi per primo)
   - **Fallimento più pericoloso** (più danno se accade, anche se meno probabile)
   - **Assunzione nascosta** (la più grande che l'utente non ha messo in discussione — spesso qui vive il valore)
   - **Piano rivisto** — cambiamenti **concreti**, ognuno mappato a un fallimento ("testa il pricing a $X con 20 persone prima di lanciarlo", non "considera il pricing")
   - **Checklist pre-lancio** (3-5 cose da verificare/mettere in piedi, ognuna previene/rileva un fallimento)

## Output

- `~/.claude/reports/premortem-<slug>-<data>.md` — transcript completo (contesto, ragioni raw, deep-dive, sintesi).
- Report HTML visuale opzionale (dark, scan-friendly, una card/fallimento) se l'utente lo vuole vedere.
- In chat: 3 frasi max — fallimento più probabile, assunzione nascosta, la revisione più importante.

## Note

- **Sempre agenti in parallelo** (il sequenziale spreca tempo e contamina). **Sempre il frame
  "è già fallito"**. **Comprensivo ma non padded.** **Non addolcire** — dì le cose scomode
  prima che lo faccia la realtà. **Revisioni concrete**, fattibili questa settimana.
- **Si compone con `@board`** (red-team multi-prospettiva *ora*) e con [[problem-validation]]
  (dove il premortem è lo stadio "risolverlo funzionerebbe?"). Diverso meccanismo, diverso output.
- Rispetta i **gate umani**: il premortem informa la decisione, non la prende.
