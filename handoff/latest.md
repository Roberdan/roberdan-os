# Handoff — 2026-08-12 (sera) · VirtualBPM: la MBR

> Sostituisce l'handoff del 2026-07-30, conservato in git a **`99ee81d`**. Se ti serve il
> contesto di gbrain/MirrorHR/le quattro decisioni del 31 luglio:
> `git show 99ee81d:handoff/latest.md`. Le tre card `todo` di roberdan-os
> (`260808-0206*`, evolve claude-code/copilot/warp) sono **ferme e non autorizzate**: non
> sono state toccate in questa sessione.

## Il filo: cosa ha chiesto Roberto

Analizzare il deck executive che manda al **presidente** (`HLS Update 8_10.pptx`) e aggiungere
a VirtualBPM una feature — **wired come "MBR" nel menu** — che aggreghi i dati dalle fonti
disponibili, li complementi con la parte qualitativa, e rigeneri **«esattamente, ma intendo
proprio esattamente»** quel deck per la monthly business review.

La parola «esattamente», ripetuta due volte, è ciò che ha deciso il design.

## Stato: FATTO e validato DONE da @thor. NON mergiato.

**Repo `VirtualBPMFy27`, branch `feat/mbr-deck`, 3 commit sopra `main` (`10cff93`):**

| commit | cosa |
|---|---|
| `1fa49ee` | la feature (35 file, 3293 righe) |
| `b88aead` | la decisione sulle 14 slide, con la motivazione |
| `013aa24` | le due gambe dell'export: da promesse a prove |

Totale `main..HEAD`: 38 file, +3708/-54. **Working tree pulito, niente pushato, nessuna PR.**

**Verde (rifatto da @thor, non solo dichiarato da me):** sequenziale 2764 test OK skipped=35 ·
sharded `tools/run_tests.py` OK, 8 shard/75 moduli · `tools/virtualbpm_doctor.py` 9/9,
0 advisories.

## La decisione di design (leggi ADR 0019 prima di toccare qualunque cosa)

Il deck porta 5 temi corporate, 103 layout, ~16 MB di loghi cliente e cornici think-cell:
**nessun renderer scritto da zero può essere «esattamente» quel deck**, e ogni mese si
allontanerebbe. Quindi VirtualBPM **non ridisegna**: apre il `.pptx` di Roberto come
**template legato** (`~/.virtualbpm/mbr-template.pptx`, fuori dal repo perché porta nomi di
clienti reali) e riscrive **in loco 47 forme dichiarate** preservando la formattazione dei run.
Rigenera solo le slide **8-11** — pipeline e i tre roadmap di capacità — che erano già output
di VirtualBPM incollato a mano ogni mese.

`docs/adr/0019-mbr-deck-from-a-bound-template.md` è l'argomento completo.

## Le due lezioni che questa sessione ha pagato care

1. **Un file statico dimenticato non degrada: spegne l'app.** `web/mbr.js` e `web/css/mbr.css`
   non erano nell'allowlist di `vbp_server/static.py` → 404 → `window.VirtualBPMMbr` undefined
   → la destrutturazione in cima a `virtualbpm.js` buttava giù l'**intero** frontend, e lo smoke
   riportava un generico "hydration timed out" che sembrava carico macchina. Diagnosi che ha
   funzionato: `git stash push -u`, un test browser, albero pulito passa ⇒ è mio.
2. **@thor ha bocciato la feature una prima volta, e aveva ragione.** Avevo scritto «provate le
   tre gambe del guardrail» avendole verificate **a mano con curl**. Lui ha tolto il controllo
   di `confirmed` dall'export, poi quello di revisione stale, e **tutti i 2753 test sono
   rimasti verdi** entrambe le volte: i test MBR provavano solo le funzioni Python nude, mai
   una richiesta HTTP, e il contratto generico saltava l'export perché la rotta è classificata
   read-only. Chiuso con `tests/test_mbr_http.py` (rig registrato in `RIG_REGISTRY`) e
   `READ_ONLY_CONFIRMATIONS`. **«Funziona oggi» e «un refactor non può romperlo in silenzio»
   sono due affermazioni diverse.**

## Aperto — sono gate di Roberto, non miei

1. **Merge / PR.** `feat/mbr-deck` non è pushato. Roberto ha chiesto (a) apri la PR,
   (b) crea le card, (c) entrambe — **e non ha ancora risposto**. È la prima cosa da chiedergli
   al risveglio.
2. **`docs/findings.md` #24 non ha una card.** `tools/render_portfolio_pptx.py` è stato
   modificato per servire l'MBR (selezione layout su tutti i master invece dell'indice fisso 6,
   rimozione placeholder ereditati) ma è **condiviso con l'export portfolio pre-esistente** e
   nessun test copre il comportamento cambiato. La suite è verde per coincidenza: nel template
   di default il layout a zero placeholder coincide ancora con l'indice 6. Deliberatamente
   **non sanato** nel PR dell'MBR (@thor concorda). Senza card, muore lì.
3. **39 blocchi su 47 si scrivono ancora a mano** — il limite onesto rispetto ad «aggregare
   dati dalle fonti disponibili». Ho verificato due candidati e sono correttamente manuali:
   - `state.billable.value` (il totale del portafoglio billable): **non derivabile**. Il campo
     `customerValue` dello
     snapshot **non è denaro**, contiene `"4 = Defined"`, `"3 = Aspirational"` — una scala di
     maturità. Sommarla come dollari sarebbe stato un errore grave con l'autorità di un calcolo.
   - I **12 numeri di intake della slide 7**: il blocco `fde` ha `openCount` e `stageUpdates`,
     ma **non** la ripartizione Americas/EMEA/Asia né gli split align/ISE-led/billable-track.
     Oggi la fonte non c'è. Restano una digitazione mensile che una lettura della casella
     intake FDE toglierebbe: **è la card successiva naturale, non aperta.**

## Decisioni prese e ancora attive

- **14 slide, non 12** (accettato da Roberto l'11/08): la capacità impagina, Americas ed EMEA
  riempiono due pagine. Forzare una pagina per regione significherebbe righe illeggibili o
  engagement caduti dal fondo. Un salto pagina si vede, una riga mancante no.
- **Cinque cifre sono suggerimenti, non derivazioni**: le caselle FDE contano la popolazione
  dell'**intake**, non il portfolio ADO. Derivarle le avrebbe **ridefinite** sotto un'etichetta
  immutata.
- **`narrativeRevision` è obbligatorio all'export** (buco trovato dopo la bocciatura, non
  segnalato da @thor): era `if expected is not None`, quindi chi taceva spegneva l'unica
  guardia della rotta — e il silenzio è ciò che produce un client vecchio.
- **Entrambe le POST muta-stato pretendono `confirmed: true`**: l'esenzione
  `UNCONFIRMED_MUTATION_ROUTES` non è stata chiesta.

## Per far ripartire il lavoro

```sh
cd ~/GitHub/VirtualBPMFy27 && git switch feat/mbr-deck
cp "HLS Update 8_10.pptx" ~/.virtualbpm/mbr-template.pptx   # se il template non c'è più
./virtualbpm.sh start          # poi voce "MBR" nel menu
python3 tools/run_tests.py     # 65 s, è ciò che gira in CI
```

**Prossima azione singola:** chiedere a Roberto (a) PR, (b) card per finding #24 + intake FDE,
o (c) entrambe. Nient'altro è in sospeso su questo filo.
