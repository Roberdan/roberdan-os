# Piano — Sistema di trading assistito → agentico (goal: €10M in 2 anni)

> **Data:** 2026-07-08 · **Richiesta:** applicazione completa per il trading — dal monitoraggio
> news all'analisi real-time, ai suggerimenti operativi su sistema esterno, fino a un sistema
> agentico autonomo che impara e migliora finché non raggiunge l'obiettivo (€10M in 2 anni).
> **Metodo:** roberdan-os — intake gate, premortem (agenti paralleli), evidence-first,
> human gates, loop protocol, kanban gated.

---

## 0. Verdetto onesto (prima di tutto — Art. Verification: no claims senza evidenza)

Il sistema si può costruire, ed è descritto sotto in dettaglio. **L'obiettivo numerico, invece,
va rinegoziato**, perché la matematica non è opinabile:

| Capitale iniziale | Per arrivare a €10M in 2 anni serve | Contesto |
|---|---|---|
| €50.000 | ~1.314% annuo composto (14,1× l'anno) | Nessuna strategia sistematica documentata al mondo lo fa in modo ripetibile |
| €250.000 | ~532% annuo (6,3×/anno) | Idem — territorio lotteria/leva estrema |
| €1.000.000 | ~216% annuo (3,16×/anno) | I migliori hedge fund della storia (Medallion) fanno ~66% lordo/anno su capitale *chiuso* |
| €2.500.000 | ~100% annuo (2×/anno) | Ancora sopra qualunque track record pubblico ripetibile |
| €10.000.000 | 0% — obiettivo già raggiunto | — |

E la tabella è ottimista: con il capital gain italiano al **26%**, per avere €10M *netti*
servono ~**€13,5M lordi** → i rendimenti mensili richiesti salgono a ~26%/mese (da €50k),
~18%/mese (da €250k), ~11,5%/mese (da €1M), **ogni mese per 24 mesi**. Calibrazione: Medallion
(centinaia di PhD, infrastruttura privata) ha fatto ~66% lordo/anno; Buffett ~20% CAGR in
carriera. Lo scenario "da €1M" richiede ~5,5× il rendimento netto di Medallion, sostenuto per
24 mesi, da una persona sola, part-time.

Un rendimento **eccellente e realistico** per un sistema sistematico retail ben fatto è il
**15–30% annuo con drawdown ≤15%**. Con €250k diventano ~€390–420k in 2 anni, non €10M.
Inseguire il numero €10M con capitale retail significa leva 10–20× — che peraltro **ESMA vieta
al retail** (cap 5:1 sulle equities, 2:1 crypto) — → **probabilità di rovina largamente
dominante** rispetto alla probabilità di successo. Il premortem (§6) lo quantifica: la causa di
morte n.1 del progetto è proprio l'obiettivo stesso, perché è l'obiettivo a dettare la leva.

**Proposta (decisione tua, gate umano #5):** teniamo €10M come *North Star* di lungo periodo,
ma il sistema ottimizza un obiettivo controllabile: **massimo rendimento composto con rischio
di rovina <1% e max drawdown 15%**, con milestone verificabili ogni trimestre (§7). Un sistema
che sopravvive e compone batte ogni sistema che punta al 500%/anno e muore al mese 4.

---

## 1. Architettura — 4 livelli (ognuno utile da solo, ognuno base del successivo)

```
L1  INGEST      news + dati mercato + macro + filings     (sempre acceso, append-only)
L2  ANALYSIS    feature, regime, sentiment LLM, segnali    (real-time + batch notturno)
L3  ADVISOR     suggerimenti operativi → Telegram/board    (TU esegui sul broker esterno)
L4  AGENT       loop autonomo: ipotesi→backtest→paper→live (gate umani sul denaro reale)
                             ▲ impara dai propri trade (journal + post-mortem automatico)
```

### L1 — Monitoraggio news & dati (il "sistema nervoso")
- **Market data:** websocket real-time + storico per backtest (equities USA, ETF, crypto).
- **News:** feed finanziari a bassa latenza + RSS + SEC EDGAR full-text (8-K, 13F) + calendario
  macro (Fed, CPI, NFP) + trascrizioni earnings call.
- **Storage:** TimescaleDB/Postgres (tick/bar) + parquet per la ricerca; tutto append-only,
  timestampato — è il "durable state" del loop protocol applicato ai dati.
- Ogni item news passa da un **classificatore LLM** (Claude Haiku per il triage di massa, Sonnet
  per gli item rilevanti): entità → ticker, direzione, magnitudine attesa, orizzonte, confidence.

### L2 — Analisi real-time
- **Feature engine:** indicatori tecnici, volatilità realizzata/implicita, flussi, breadth,
  correlazioni; **regime detection** (trend/range/crisis) — le strategie si accendono/spengono
  per regime.
- **Ricerca notturna (batch):** generazione ipotesi di strategia → backtest vettorizzato con
  costi e slippage realistici → walk-forward + purged cross-validation (anti-overfitting) →
  report. Questo è il motore che "impara" davvero, non l'LLM che improvvisa intraday.
- **Sentiment/eventi LLM:** aggregazione news per ticker/settore, delta rispetto al consenso.

### L3 — Advisor (suggerimenti per esecuzione manuale su sistema esterno)
- Ogni segnale diventa una **proposta operativa completa**: ticker, direzione, entry, stop,
  target, size suggerita (frazione di Kelly / vol-targeting), rationale in 3 righe, evidenza
  (backtest della strategia madre + news trigger), scadenza della validità.
- Consegna: **bot Telegram** (mobile-first) + dashboard web locale (board dei segnali, P&L,
  esposizione, drawdown). Tu esegui sul tuo broker; il sistema poi **riconcilia** (import
  eseguiti) e tiene il **trade journal** — ogni trade chiuso genera un post-mortem automatico.
- Questo livello è **utile da subito e a rischio zero**: nessuna chiave di esecuzione.

### L4 — Sistema agentico (l'obiettivo finale, con i gate di roberdan-os)
Il loop segue il **loop protocol** del repo, applicato al trading:

```
state:              portfolio.db + strategy-registry + .agent-state/trading.jsonl (cursor)
terminal-condition: MAI "should work" → equity curve live ≥ soglia milestone di fase,
                    verificata da thor contro l'estratto conto broker (ground truth)
checkpoint:         1 commit per fase + receipt.sh per ogni run (backtest, ordine, riconcilia)
escalation:         2 strategie consecutive bocciate in paper → review di board/socrates
stuck:              drawdown > limite o 2 cicli senza progresso → HALT + report, non loopare
```

- **Ciclo di apprendimento:** `ipotesi → backtest → (se supera i gate) paper trading ≥4 settimane
  → (se il live-paper conferma il backtest entro tolleranza) proposta di promozione a capitale
  reale → GATE UMANO → live con size minima → scaling graduale a regole`.
- **Chi decide cosa:** l'agente è autonomo su ricerca, paper e gestione ordini *entro i limiti
  di rischio scritti nel risk-config firmato da te*. **Ogni promozione a denaro reale, ogni
  aumento di size, ogni nuova asset class = human gate #3 (spesa reale)** — non negoziabile,
  è nella costituzione del repo.
- **Kill-switch a strati:** (a) circuit breaker software (drawdown giornaliero/totale, n. ordini
  /min, esposizione max); (b) limiti impostati lato broker (il broker li applica anche se il
  software impazzisce); (c) chiavi API **senza permesso di prelievo**, IP-whitelisted; (d) un
  comando `HALT` da Telegram che flatten-a tutto.
- **Auto-miglioramento = meta-loop di roberdan-os:** il sistema *propone* modifiche a strategie
  e parametri con evidenza (report in `proposals/`), non si auto-applica mai su risk-config e
  capitale — stesso principio ADR-0001 (self-proposing, never self-applying).
- **Interfacce agentiche già pronte:** Alpaca ha un **MCP server ufficiale** (61 tool: quote,
  ordini, posizioni, opzioni) e IBKR un'integrazione MCP ufficiale — perfetti per il paper
  agentico di fase 4. Per il live, però, tool custom sottili sopra i nostri client broker/dati
  (Claude Agent SDK) restano più controllabili di MCP di terze parti: il rischio (F5) impone
  che i check deterministici e la submission ordini vivano in codice nostro, con limiti
  hard-coded fuori dalla portata dell'LLM.

---

## 2. Servizi esterni da integrare (verificati a luglio 2026 — il panorama EU è appena cambiato)

**Flag EU/IT critici (freschi):** **Binance è inutilizzabile dall'Italia dal 2026-07-01** (niente
licenza MiCA — solo prelievi); **USDT è ristretto** sulle venue EU regolate → coppie in EUR/USDC;
gli **ETF USA non sono acquistabili** dal retail EU (PRIIPs/KID) → equivalenti UCITS o opzioni;
Polygon.io si è **rinominato Massive**; la libreria `ib_insync` è morta → si usa il successore
**`ib_async`**; l'API di X/Twitter è fuori budget (pay-per-read) → si salta.

| Livello | Servizio | Ruolo | Costo indicativo | Note EU/IT |
|---|---|---|---|---|
| Broker | **Interactive Brokers (IBIE)** — TWS API + Client Portal API, Python `ib_async` | Esecuzione multi-asset + **conto paper nativo** + dati base | API gratis; commissioni da ~$1/ordine; dati RT US ~$14,50/mese | **Broker primario**: MiFID II via Irlanda, ha anche un'**integrazione MCP ufficiale** (2026). IB Gateway 24/7 su VPS |
| Broker (2ª venue) | **Alpaca** — REST/WS + **MCP server ufficiale v2 (61 tool)** | Paper trading gratuito eccellente, terreno ideale per gli esperimenti agentici L4 | commission-free, API gratis | Da apr 2026 ha entità EU (acquisizione WealthKernel, equities Xetra): verificare onboarding retail IT prima di dipenderne |
| Crypto | **Kraken** (MiCA, passported) o Bitvavo; Coinbase come riserva | Mercato 24/7 = palestra per L4, websocket dati **gratuiti**, CCXT | commissioni ~0,16/0,26% | **Non Binance** (vedi sopra); coppie EUR/USDC |
| Dati (partenza) | **IBKR bundle ($14,50/mese) + Finnhub free (60 call/min)** + SEC EDGAR + FRED | Quote RT US, news, fundamentals, calendario earnings/macro | ~€15/mese | Basta per un sistema a segnali su chiusura barra (il nostro orizzonte, per il premortem F4) |
| Dati (scala) | **Massive/Polygon** Stocks Developer $99 + Options $29–199; **Databento** pay-as-you-go per storico/OPRA | Full SIP real-time + ricerca su book/options | $60–400/mese | Solo quando una strategia validata lo richiede — mai prima (regola free-tier §4) |
| Dati EU/EOD | EODHD | EOD globale + Borsa Italiana/Xetra, fundamentals | ~€20/mese | Il più economico per coverage EU |
| News | **Finnhub free + Marketaux** (~$29–50/mese) + EDGAR full-text + RSS (IR aziendali, Fed/ECB) | Feed news + sentiment + filings | €0–50/mese | Benzinga (>$500/mese) solo se la latenza sulle headline diventasse l'edge — per il premortem F4, non lo sarà |
| Macro | FRED (gratis) + calendario Finnhub | Regime/eventi | €0 | — |
| LLM | **Anthropic API**: Haiku 4.5 ($1/$5 per Mtok) per il triage di massa, Sonnet 5 ($3/$15) per l'analisi, Opus 4.8 ($5/$25) per orchestrazione/ricerca strategie | Interpretazione news → segnali strutturati, post-mortem, generazione ipotesi | **~$20–100/mese** con Batch API (−50%) e prompt caching | Structured outputs per segnali machine-parseable; l'LLM analizza e propone, **mai** tocca ordini/rischio direttamente |
| Backtest | **vectorbt** (ricerca vettorizzata, migliaia di varianti/secondo) → **NautilusTrader** (event-driven, **stesso codice backtest→paper→live**, adapter IB/Polygon/Databento/crypto) | Motore di validazione e di produzione | open source (VectorBT PRO ~$29/mese opzionale) | backtrader è in maintenance-mode: non usarlo. QuantConnect/LEAN = alternativa hosted con lock-in |
| Ops | Telegram Bot (gratis, **inline button approva/rifiuta** = human gate mobile), Grafana Cloud free + Prometheus, healthchecks.io (dead-man switch), **VPS Hetzner CX22 €3,79/mese** (CX32 €6,8 con IB Gateway) | Alert, monitoring, uptime 99,99% | ~€5–10/mese | VPS EU batte il server casalingo (95% vs 99,99% uptime) per qualunque cosa tenga ordini aperti |
| Fisco | Journal trade → export per commercialista (regime dichiarativo, quadro RW, IVAFE) | Capital gains 26%, compliance | — | Commercialista con esperienza trader **da fase 0** (premortem F7) |

**Budget: stack minimo ~€25–60/mese + LLM** (IBKR bundle + Finnhub free + Hetzner + Telegram) —
è quello delle fasi 0–3. **Stack completo ~€300–600/mese + LLM** solo quando una strategia
validata giustifica dati migliori. Regola vincolante (premortem F6): **costi fissi ≤0,25%/mese
del capitale**, e nessun abbonamento prima che la strategia che lo richiede sia validata su
dati free/delayed.

---

## 3. Integrazione con roberdan-os (l'app è un "organo" del sistema, non un silo)

- **Repo nuovo dedicato** (es. `~/GitHub/trading-os`), registrato con `kb init trading-os`:
  board kanban federata, card con `repo: trading-os`.
- **Loop protocol:** ogni fase = card con `dod:` + `acceptance:`; `todo→doing` lo approvi tu
  (`kb start … --by roberto`), `doing→done` lo valida **thor con evidenza empirica** (equity
  curve, test verdi, estratto broker — mai il transcript dell'agente).
- **Agenti:** `baccio` progetta/implementa · `rex` review del codice · `luca` security review
  (chiavi API, sandbox, kill-switch) · `socrates`/`board` red-team sulle strategie e sulle
  decisioni di capitale · `thor` unico gate del done · `wanda` orchestrazione del loop notturno.
- **Skills:** `premortem` a ogni promozione di strategia · `verify-done` prima di ogni gate ·
  `ship`/`review` sul codice · `focus-group` non serve qui (il "mercato" è il giudice).
- **Memoria:** ogni post-mortem di trade e ogni strategia bocciata/promossa finisce nel vault
  via `learn/` → è così che il sistema "impara costantemente" in modo durevole, cross-sessione.
- **Human gates ereditati:** #3 (spesa reale = ogni euro a mercato), #4 (mai cancellare lo
  storico trade/dati), #5 (decisioni di capitale e leva), #7 (cambi architetturali al risk engine).

---

## 4. Roadmap a fasi — ogni fase con Definition of Done verificabile

**Regola d'ordine (dal premortem):** prima si valida l'edge col minimo indispensabile, poi si
costruisce la piattaforma — mai il contrario. Se dopo la fase 2 nessuna strategia supera i gate,
il progetto si ferma lì per costituzione (e avrà comunque prodotto L1–L3, utili da soli): meglio
scoprirlo con €0 a mercato. Budget dati/servizi: **free tier finché l'edge non è validato**
(dati delayed, RSS, EDGAR) — una strategia il cui edge sparisce su dati ritardati di 15 minuti
era un latency-trade che avresti perso comunque.

| Fase | Contenuto | DoD (thor-verificabile) | Durata |
|---|---|---|---|
| **0 — Fondamenta minime** | Repo, risk-config firmato, conto IBKR paper, ingest L1 minimo (1 feed dati + EDGAR + 2 feed news su free tier), storage | Dati che fluiscono da 7 giorni senza buchi; `kb` board attiva | 2 sett. |
| **1 — Radar** | Classificatore news LLM, digest 2×/giorno su Telegram, dashboard base | 10 giorni di digest; precision del triage ≥80% su campione etichettato a mano | 3 sett. |
| **2 — Ricerca** | Motore backtest con costi/slippage, walk-forward, 3 famiglie di strategie (trend-following ETF, mean-reversion, event-driven news) | ≥1 strategia che supera walk-forward con Sharpe ≥1 *dopo* i costi, su dati out-of-sample | 4–6 sett. |
| **3 — Advisor** | Segnali completi (entry/stop/size/rationale) su Telegram, journal + riconciliazione, post-mortem automatico | 4 settimane di segnali tracciati; hit-rate e P&L teorico riportati onestamente | 4 sett. |
| **4 — Paper agentico** | L4 completo su conto paper IBKR: esecuzione autonoma, circuit breaker, HALT, receipts | 4+ settimane paper; slippage paper-vs-backtest entro tolleranza; kill-switch testato con fault-injection | 6 sett. |
| **5 — Live gated** | Capitale reale minimo (size che non fa male), scaling a regole solo dopo milestone | 3 mesi live: tracking error vs paper entro banda; drawdown < limite; **ogni scaling = tuo gate** | continuo |

Milestone trimestrali sul North Star: equity ≥ piano composto concordato (es. +5%/trimestre
all'inizio); 2 trimestri sotto piano → si torna in fase ricerca, non si alza la leva. **La leva
non è mai la risposta a un ritardo sul piano** — è la regola che tiene in vita il progetto.

---

## 5. Card kanban proposte (da creare con `kb add` sul tuo Mac — contenuto gitignored)

```
kb add "Fase 0: fondamenta trading-os (repo+risk-config+ingest 7gg senza buchi)" --repo trading-os \
   "ingest L1 attivo 7 giorni, risk-config firmato, conto IBKR paper aperto" \
   "thor: query sul DB dati = 0 gap >5min su 7gg; file risk-config.yaml committato e approvato da Roberto"
kb add "Fase 1: radar news→Telegram (triage LLM ≥80% precision)" --repo trading-os ...
kb add "Fase 2: motore backtest + 1 strategia Sharpe≥1 out-of-sample dopo costi" --repo trading-os ...
kb add "Fase 3: advisor con journal e post-mortem (4 settimane tracciate)" --repo trading-os ...
kb add "Fase 4: agente paper 4 settimane + kill-switch fault-injected" --repo trading-os ...
kb add "Fase 5: live gated con scaling a regole" --repo trading-os ...
```

Gate `todo→doing`: tuo, come sempre. Nessuna fase parte da sola.

---

## 6. Premortem — "è il 2028-07, il progetto è morto: perché?" (sintesi)

| # | Causa di morte | Assunzione rotta | Segnale precoce | Mitigazione nel piano |
|---|---|---|---|---|
| 1 | **L'obiettivo stesso**: per inseguire €10M si è alzata la leva dopo i primi ritardi → drawdown 60% al primo shock di regime → capitale e fiducia azzerati | "Un sistema abbastanza intelligente può fare 200%+/anno" | Size/leva aumentate dopo un trimestre sotto piano | §0: obiettivo rinegoziato; regola "la leva non risponde ai ritardi"; risk-of-ruin <1% hard-coded |
| 2 | **Overfitting**: la strategia stellare in backtest muore live (data-snooping, costi sottostimati) | "Il backtest predice il live" | Paper P&L ≪ backtest P&L già nelle prime 2 settimane | Walk-forward + purged CV; costi/slippage pessimistici; 4 settimane paper obbligatorie; tolleranza backtest-vs-paper esplicita |
| 3 | **Costi che mangiano l'edge**: commissioni+slippage+26% fisco+dati+LLM > alpha su capitale piccolo | "L'edge sopravvive ai costi" | Rendimento lordo positivo, netto ~0 | Costi nel backtest fin dal giorno 1; frequenza operativa bassa; regola costi fissi <1%/anno del capitale |
| 4 | **Latenza LLM vs mercato**: la "news edge" è già nei prezzi quando l'LLM ha finito di ragionare | "Leggere le news più in fretta degli altri" | Segnali news con P&L negativo dopo il primo minuto | Le news pilotano *filtri e regime*, non ingressi al millisecondo; orizzonti da ore/giorni, non secondi |
| 5 | **Agente con le chiavi**: bug o prompt-injection nel feed news → ordini errati in raffica | "Il software si comporterà come nei test" | Ordini anomali in paper, feed con contenuti adversarial | Kill-switch a 3 strati (§1-L4); chiavi senza prelievo; fault-injection test come DoD di fase 4; news = dato untrusted, mai comando |
| 6 | **Abbandono/tempo**: il progetto compete con Microsoft + Fight the Stroke; dopo 3 mesi il loop notturno gira ma nessuno guarda i report | "Avrò tempo di supervisionare" | Report non letti per 2 settimane | Fasi brevi con valore immediato (L1-L3 utili da soli); digest 2 righe su Telegram, non dashboard da studiare; auto-checkpoint |
| 7 | **Compliance/fisco ignorati**: regime dichiarativo con broker estero (quadro RW, IVAFE, migliaia di righe), leva ESMA-capped (5:1 equities, 2:1 crypto) e PRIIPs che bloccano gli ETF USA del backtest → la strategia *deployabile* è più debole di quella testata | "I rendimenti del backtest ≈ rendimenti sul conto" | Il backtest contiene strumenti/leve che un conto retail Consob/ESMA non può tenere; nessun commercialista consultato prima del live | Backtest solo sulla strategia deployabile (cap ESMA, strumenti UCITS, compounding al netto del 26%); commercialista con esperienza dichiarativo-trader da fase 0; mai optare per status "professional" o venue non regolate per "sbloccare" l'obiettivo |
| 8 | **Decadimento silenzioso senza attribuzione**: l'alpha decade col regime, il vendor cambia schema, il modello LLM viene aggiornato e la distribuzione dei segnali cambia overnight — e non si riesce a dire se è edge finito, bug o varianza → il sistema viene spento in silenzio | "Se funziona una volta, continua a funzionare; se si rompe me ne accorgo" | Non saper rispondere in 5 minuti a "P&L di ieri per segnale, per strumento, vs atteso?"; gap dati >24h scoperti a posteriori | Attribuzione e monitoring shippati *con* la prima strategia, non dopo: expected-vs-realized per segnale, allarmi data-freshness, tripwire statistico pre-dichiarato ("Sharpe live 60gg < X → torna in paper da solo") |

- **Fallimento più probabile (esito modale, mese 4–6):** #6+#2 — una piattaforma bellissima e
  incompiuta, un backtest overfittato mai sopravvissuto al live, e il day job (Microsoft + FTS)
  che si riprende le ore. Antidoto strutturale: **ordine di build invertito** — si valida l'edge
  con il minimo indispensabile (un segnale, uno strumento, un CSV, conto paper) e ogni layer
  successivo si "guadagna" superando l'evidence bar del precedente (è esattamente il gate
  dod/acceptance del kanban).
- **Fallimento più pericoloso:** #1+#5 — l'obiettivo €10M che impone la leva, e l'agente
  autonomo che esegue la rovina (Knight Capital perse $440M in 45 minuti *con* uno staff di
  compliance). È l'unico fallimento che non lascia seconda possibilità: le mitigazioni di #1 e
  #5 sono non negoziabili.
- **Assunzione nascosta più grande:** *che il collo di bottiglia sia l'ingegneria.* Non lo è:
  la vera domanda aperta è **se un operatore retail solo, che legge news pubbliche via LLM,
  abbia un edge dopo-costi qualsiasi**. La matematica dice che l'obiettivo non è raggiungibile
  con l'edge a capitale retail — solo *tentabile* con la leva, che trasforma il progetto da
  "costruire software" a "comprare un biglietto della lotteria con rischio di rovina ≈ 1".
  L'asset costruibile e prezioso è un **sistema live verificato a Sharpe positivo + la
  competenza per gestirlo** — e quell'asset viene *distrutto*, non creato, dall'ancoraggio
  a €10M in 24 mesi.

**Disciplina anti-overfitting (vincolante, da #2):** ogni esperimento è **pre-registrato**
(ipotesi, parametri, periodo out-of-sample dichiarati *prima* del run, in un log append-only —
`receipt.sh` fa già questo); esiste un holdout finale mai toccato; i backtest "LLM legge news
storiche" sono contaminati per costruzione (il training data del modello contiene quelle news e
i movimenti successivi) → per i segnali LLM **conta solo il forward-test**.

---

## 7. Decisioni aperte (tue — gate umano; la fase 0 può partire anche senza, ma queste cambiano dimensionamento e priorità)

1. **Capitale dedicato** (e quota "sopravvivenza" mai a rischio): dimensiona tutto — costi
   sostenibili, size minime, aspettative oneste.
2. **Asset class di partenza:** proposta = ETF/equities USA (liquidi, dati ottimi) + crypto come
   palestra 24/7 per L4 con size simboliche. Opzioni/futures solo dopo la fase 3.
3. **Broker:** proposta = Interactive Brokers (paper nativo, API matura, disponibile in Italia).
4. **Perimetro di autonomia iniziale di L4:** proposta = piena autonomia in paper, live solo
   con promozione esplicita per strategia e per size.
5. **Accetti la riformulazione dell'obiettivo (§0)?** North Star €10M, obiettivo operativo
   = massimo compounding con rovina <1% e milestone trimestrali.

---

*Piano prodotto in roberto-mode: evidence-first, premortem incluso, gate umani preservati.
Nessun euro va a mercato senza il tuo sì esplicito — per costituzione, non per prudenza retorica.*
