---
name: focus-group
description: "Simula un focus group / validazione con utenti reali: crea un pool di agenti-persona sul profilo richiesto + un moderatore + un consolidatore. Valida problemi, definizioni, ipotesi, app, feature, usabilità, feedback. Multi-modo (focus group, interviste 1:1, usability test, micro-survey). TRIGGER: 'valida questa ipotesi/idea/feature', 'cosa ne pensano gli utenti', 'simula un focus group', 'testa l'usabilità', 'crea un panel di early adopter', 'feedback da utenti reali su X'. SÌ quando serve la voce dell'utente prima di costruire/decidere."
providers: [claude, copilot, codex]
---

# focus-group

Dato un **tema + contesto**, genera un panel di **agenti-persona** che si comportano come
utenti reali del profilo richiesto, un **moderatore** che conduce, e un **consolidatore** che
sintetizza. Serve a portare la voce dell'utente *prima* di costruire o decidere.

## Il rischio #1 — anti-sycophancy (non negoziabile)

Gli utenti simulati sono **compiacenti per default**: direbbero "bella app!". È teatro inutile.
Ogni persona DEVE essere ancorata a:
- **frustrazioni reali, alternative già in uso, budget, tempo, scetticismo**, costo di switch;
- il diritto di dire "non lo userei", "non capisco perché dovrei", "già lo faccio con X";
- **niente lode senza motivo concreto** — un "mi piace" vale solo con il perché e il contesto d'uso.
Il moderatore **scava la frizione**, non raccoglie applausi. Il consolidatore **pesa il segnale
negativo** più di quello positivo (il negativo specifico è più informativo).

## Panel: persistenti + ad-hoc

- **Persistenti** (riusabili, coerenza cross-sessione): salvati nel vault come note
  `type: focus-persona` in `focus-panels/<panel>/` (es. `caregiver-fts`, `early-adopter-tech`).
  Riusa un panel esistente quando il tema combacia → confronti longitudinali.
- **Ad-hoc:** genera personas fresche dal tema/contesto quando non c'è panel adatto.
  A fine sessione, **proponi** (gate umano) di promuovere le personas utili a panel persistente.

### Generare personas (diverse, non cloni)
Da una audience-spec se fornita (es. "caregiver di bambini con disabilità, 30-45, Italia"),
altrimenti derivate dal tema. Diversifica sugli assi che contano: bisogno/job-to-be-done,
competenza tecnica, budget, contesto d'uso, **livello di scetticismo**, alternativa attuale.
Default **5-8** personas. Ognuna: nome, 1-riga di background, goal reale, frustrazione,
alternativa attuale, cosa la farebbe dire di no. Grounding dal vault se pertinente (gbrain).

## Modi (scegli in base all'intento)

| Modo | Quando | Come |
|---|---|---|
| **Focus group** moderato | esplorare percezioni, far emergere temi, dinamica di gruppo | moderatore pone stimoli, personas rispondono e **reagiscono tra loro** (accordo/disaccordo) |
| **Interviste 1:1** | profondità, evitare groupthink, temi sensibili | moderatore ↔ una persona per volta, in parallelo (Agent tool) |
| **Usability test** task-based | testare app/feature/flusso | dai un task concreto; la persona "prova", riporta friction/blocchi/confusione, non opinioni |
| **Micro-survey** quant | segnale numerico rapido | domande chiuse a tutte le personas → distribuzione (es. 6/8 non pagherebbero) |

## Flusso

1. **Setup:** chiarisci tema, intento (validare problema? definizione? ipotesi? usabilità?),
   audience, e **cosa conta come successo/kill**. Scegli il modo. Cerca un panel esistente.
2. **Panel:** riusa o genera personas (in parallelo se molte).
3. **Sessione:** il moderatore conduce nel modo scelto. Personas **in-character**, ancorate,
   libere di dissentire. Group-mode: fai emergere accordi/disaccordi reali.
4. **Consolidamento:** il consolidatore produce il report.

## Output — report strutturato

`~/.claude/reports/focus-group-<tema>-<data>.md`:
- **Verdetto** in 3 righe: il problema/l'ipotesi regge? segnale netto.
- **Temi** (ordinati per forza del segnale) con **quote verbatim** delle personas.
- **Accordi vs disaccordi** (dove il panel diverge — spesso il pezzo interessante).
- **Severità/frequenza** del problema percepito; **willingness** (userebbe? pagherebbe?).
- **Kill-signals** emersi (cosa farebbe fallire l'idea).
- **Azioni** concrete + **confidenza** (è simulazione: dillo — orienta, non sostituisce utenti veri).

## Note

- **Onestà sul limite:** è simulazione. Ottima per *scoprire domande, ipotesi, blind-spot e
  friction*; **non** un sostituto di utenti reali per numeri di conversione. Dillo nel report.
- Si compone con [[premortem]] (stress-test della soluzione) dentro [[problem-validation]].
- Personas mai basate su persone reali identificabili senza consenso; rispetta i blocchi privacy.
