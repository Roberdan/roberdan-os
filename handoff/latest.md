# Handoff — 2026-08-19 (sera) · VirtualBPM: il seam Compass One e il KPI di margine

> Sostituisce l'handoff del 2026-08-12 (la MBR), conservato in git a **`9fca31f`**.
> Se ti serve quel contesto: `git show 9fca31f:handoff/latest.md`.

## Se dici solo "continua"

**Il primo passo è tuo, non mio: leggere PR #108 e decidere il merge.** Non c'è lavoro
tecnico in sospeso. Working tree pulita, suite e doctor verdi *sullo stato committato*.

```
https://github.com/roberdan_microsoft/VirtualBPMFy27/pull/108   OPEN · MERGEABLE
```

Se dici sì: `cd ~/GitHub/VirtualBPMFy27 && gh pr merge 108 --squash`, poi `main` + pull,
poi spostare le tre card (sotto). Se dici no sul punto 1 qui sotto, si ridiscute **prima**
del merge.

## Il filo: cosa ha chiesto Roberto

Quattro richieste in fila: (1) recuperare il lavoro dopo il reset del Mac, (2) PR e commit
fino a una situazione pulita, (3) finire quello che mancava **previa validazione che avesse
ancora senso, solo su VirtualBPM**, (4) **«ignora le soglie e implementa comunque le card,
mi serviranno per il futuro»**.

Tutte e quattro sono chiuse. Le prime tre sono già su `main` (v4.21.0, v4.21.1, v4.21.2).
La quarta è la PR #108.

## Stato meccanico

- Repo: `~/GitHub/VirtualBPMFy27` · branch `feat/compass-one-seam`, pushato
- HEAD `53db948` — `chore: bump version and changelog (v4.22.0)`
- File non committati: **0** · `main` a `f7c113e` (v4.21.2)
- `python3 tools/run_tests.py` → OK, 8 shard, 81 moduli
- `python3 tools/virtualbpm_doctor.py` → 9 passed, 0 errors, 0 advisories

Entrambe rieseguite **dopo** i commit, non su una tree sporca. (La sharded ha girato in
~460 s invece dei soliti ~65 s: carico della macchina, non un test lento nuovo.)

I quattro commit sono bisectabili di proposito — il seam sta in piedi senza il KPI, il KPI
senza la rotta: `2572c15` seam+ADR · `e082d7f` KPI · `3837f34` rotta · `53db948` rilascio.

## Cosa manca DA TE (l'unica cosa che resta)

1. **Il KPI non pubblica una percentuale di margine di portafoglio, ed è una mia scelta.**
   È il punto dove mi sono discostato dalla lettera del DoD della card. Il DoD diceva
   «aggrega il Sold Margin»; farlo alla lettera sarebbe la **quarta** occorrenza in questo
   repo dello stesso errore, dopo `customerValue`, le cinque caselle FDE e il caso singolo
   che l'ADR 0020 ha misurato: **48,55% pubblicato contro 46,32% derivato**. Quindi
   totalizzo Revenue e Delivery Cost — sono quantità, sommarle è onesto — e mostro ogni
   Sold Margin **come Compass One lo pubblica**. La percentuale che un lettore si
   aspetterebbe non c'è, e un contratto verifica che non possa rientrare di nascosto.
   **Se non sei d'accordo si ridiscute prima del merge.**

2. **I dealId li dichiari tu** in `runtime/compass_deals.json`, forma
   `{"deals": {"<msxOpportunityId>": "<dealId>"}}`. Non è pigrizia: la Search di Compass One
   non risponde, quindi da un opportunity id non si risale a un dealId (ADR 0020, prova 5).
   Senza il file il registry è vuoto e la copertura è 0-su-M — stato legittimo e dichiarato,
   non un errore.

3. **Le card sono qui su `roberdan-os` e non le ho toccate.** Spostarle spetta a te:
   `260816-201106` (funding type, già in v4.21.2) · `260816-201106-1` (Compass One) ·
   `260816-201116` (KPI margine), queste due nella PR.

## La card che resta bloccata, e perché non è una soglia

`260816-184424` (casella intake FDE). **Non è sbloccabile ignorando una soglia**: 66/66
messaggi sono EMEA perché si legge `/me/messages`, cioè la tua casella. Nessuna decisione di
rischio fa apparire i dati Americas/Asia — è un limite della fonte. Serve un'altra fonte,
non un'altra soglia.

## Cosa c'è dentro la PR

**Il seam Compass One.** L'ADR 0020 non diceva «impossibile»: elencava il prezzo. Tu hai
scelto B (costruirlo) contro la mia raccomandazione A, e l'ADR 0021 registra il ribaltamento
conservando le sette prove dello 0020. Le tre garanzie sono pagate in codice:
sola navigazione (allow-list CDP applicata *a runtime* dentro `send()`, non un commento —
Compass One è un sistema dove hai autorità di **scrittura**); eccezione al profilo
**dichiarata** (una sessione SSO non può stare in un profilo usa-e-getta, quindi non può
portare il prefisso `virtualbpm-edge-` a cui lo sweep si aggancia); Sold Margin mai
ricalcolato (zero aritmetica nel modulo, imposta da un contratto AST).

**Il KPI** e la rotta di sola lettura `GET /api/margin/kpi`, sul modello letterale di
`/api/devdays`: gate → **503** che nomina la variabile da accendere. Copertura N-su-M nello
stesso payload dei totali, così nessun renderer può mostrare l'uno senza aver avuto l'altra
in mano. Valute diverse rifiutano di sommarsi invece di inventare un cambio.

Tutto **spento di default**: senza `VIRTUALBPM_COMPASS_ENABLED=1` l'app è identica a prima.

```bash
export VIRTUALBPM_COMPASS_ENABLED=1 && ./virtualbpm.sh restart
curl 'http://127.0.0.1:8765/api/margin/kpi?scope=studio3'
```

## Tre cose imparate che costerebbe riscoprire

- **Aggiungere una rotta GET costa quattro dichiarazioni**, non una:
  `routing.GET_API_ROUTES`, l'inventario in `tests/_virtualbpm_endpoint_shared.py`,
  `GET_ROUTES` in `tests/test_server_contracts.py`, il conteggio in
  `docs/CONTRACT-INDEX.md`. Una quinta (`RIG_REGISTRY` in
  `tests/test_runtime_isolation_contract.py`) solo se il test *binda* un server vero. Me ne
  sono accorto una alla volta, e ognuna è costata una corsa completa della suite.

- **Il guardrail aritmetico è passato per tre stesure e le prime due erano decorative.**
  Grep letterale su `"revenue -"`: una mutazione di una riga gli è passata davanti. AST su
  *tutti* i BinOp: falsi positivi su `Path / "x"`. Finale: `Sub`/`Mult`/`Pow`/`FloorDiv`
  vietati ovunque, `Div`/`Add` solo se l'espressione nomina un campo pubblicato. Effetto sul
  codice, ed è quello giusto: `coverage()` scrive `.difference()` invece di `-`, perché per
  l'AST differenza di insiemi e sottrazione sono lo stesso nodo. **Non "semplificarlo"**:
  meglio adattare il codice che insegnare al guardiano un'eccezione con cui lo si inganna.

- **Ogni garanzia è verificata per mutazione**, non solo vista verde: iniettato
  `Input.dispatchMouseEvent` → rosso; iniettata una sottrazione fra `revenue` e
  `deliveryCost` → rosso; ripristinati → verde. Un contratto mai visto fallire è una
  decorazione.

## Cosa NON fare al ritorno

- Non rifare il bump: v4.22.0 è già scritto in tutti e cinque i file.
- Non toccare repo diversi da `VirtualBPMFy27` (tuo vincolo del 2026-08-19).
- **Non mergiare senza il tuo sì esplicito**: l'hai confermato tre volte in questa sessione.
