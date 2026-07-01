---
name: problem-validation
description: "Aiuta a capire QUALI problemi vale la pena risolvere, non solo a risolverli. Orchestra: scoperta/validazione del problema con utenti (focus-group) → prioritizzazione (severità×frequenza×raggiungibilità×fit) → stress-test della soluzione (premortem). TRIGGER: 'vale la pena risolvere X', 'è un problema vero', 'quale problema attacco', 'dovrei costruire questo', 'validiamo prima di costruire', 'prioritizza questi problemi', 'is this worth building'. SÌ a monte di ogni build/investimento non banale."
providers: [claude, copilot, codex]
---

# problem-validation

Il sistema non deve solo risolvere problemi, ma dire **quali valgono**. Questo skill è
l'orchestratore a monte: prima di costruire, valida che il problema sia reale, che valga,
e che la soluzione reggerebbe. Si compone dagli altri due skill + gstack.

## Quando

Prima di ogni build/investimento/pivot non banale. Se qualcuno dice "costruiamo X" → prima
chiedi "il problema dietro X è reale, frequente, e vale?". Se è un'idea vaga → prima
`gstack:spec` per renderla concreta, poi valida.

## Pipeline (3 stadi, gate umano tra gli stadi importanti)

### 1. Il problema esiste? → [[focus-group]]
Porta la voce dell'utente sul **problema**, non sulla soluzione. Modo tipico: focus group +
interviste 1:1. Domande: il problema esiste davvero? quanto fa male? come lo risolvono oggi?
Output: il problema è **reale/immaginato**, con evidenza (quote, disaccordi, kill-signals).
*Se il problema non regge qui → STOP. Hai appena risparmiato un build inutile.*

### 2. Vale la pena? → rubrica di prioritizzazione
Se ci sono più problemi candidati, scora ognuno (1-5) e rendi il trade-off esplicito:

| Criterio | Domanda |
|---|---|
| **Severità** | quanto fa male quando accade? |
| **Frequenza** | quanto spesso accade / quante persone? |
| **Raggiungibilità** | riesco davvero a raggiungere e servire chi ce l'ha? |
| **Fit strategico** | è nella mia missione/leva unica? (per Roberto: disabilità/inclusione, Fight the Stroke) |
| **Willingness** | pagherebbero / cambierebbero comportamento? (dal focus-group) |
| **Costo di sbagliare** | se attacco il problema sbagliato, quanto perdo? |

Score basso su Raggiungibilità o Fit → di solito è un no, anche se Severità è alta.
Non sommare ciecamente: rendi visibile *dove* sta il rischio.

### 3. La soluzione reggerebbe? → [[premortem]]
Sul problema vincente + la soluzione proposta, lancia il premortem: "è fra 6 mesi, la
soluzione è fallita, perché?". Espone le assunzioni e produce il piano rivisto + checklist.

## Sfrutta gstack (non duplicare)

- **`gstack:spec`** — trasforma l'intento vago in spec eseguibile *prima* di validare.
- **`gstack:office-hours`** — pressione YC-style sul business/go-to-market *dopo* la validazione.
- **`gstack:plan-ceo-review` / `plan-eng-review`** — quando la validazione diventa un piano.
Questo skill sta **a monte** (il problema vale?); gstack aiuta a valle (come eseguirlo).

## Output

`~/.claude/reports/problem-validation-<tema>-<data>.md`:
- **Raccomandazione netta:** costruisci / non costruire / prima raffina — con il perché.
- Evidenza dal focus-group, tabella di prioritizzazione, sintesi del premortem.
- **La verità irriducibile:** qual è la vera cosa da decidere (stile first-principles / `@socrates`).

## Note

- **Bias-to-kill:** il default di questo skill è **scettico** — è più prezioso dire "non vale"
  che confermare. Componilo con `@socrates` (verità irriducibile) e `@board` (red-team).
- È simulazione + framework: **orienta la decisione, non la prende** (gate umano).
- Voce/decisione "come Roberto" → si compone col twin ([[roberdan-twin]]).
