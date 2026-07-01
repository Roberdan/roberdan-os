# ADR — Always-on roberdan-os: sicurezza dell'esposizione della memoria (G5)

**Status:** Proposed (2026-07-01) · advisory · **Decide:** Roberto (gate umano — spesa/architettura/esposizione memoria)
**Security lens:** luca-mode (zero-trust, OWASP-style) applicato a un setup personale/indie
**Relates to:** `docs/always-on-design.md` (Path A/B/C), `kanban/todo/G5-always-on.md`, `kanban/todo/FtS-ingest.md`

> Questo documento è **materiale per decidere**, non una decisione. G5 resta un gate umano.
> Nessuna card kanban viene mossa.

## Contesto del rischio

G5 vuole rendere la memoria di roberdan-os interrogabile dall'app Claude su iPhone quando il
Mac è spento, esponendo il **MCP server di gbrain** su un host always-on con auth (bearer token).

Il rischio non è teorico. La memoria non è "il vault e basta": il brain gbrain è **multi-source**
(verificato con `gbrain sources list`). Un endpoint MCP mal-scopato non espone il vault — espone
**tutto il brain**:

| Source | Pagine | Sensibilità |
|---|---|---|
| `vault` | 291 | Note personali + (post FtS-ingest) **finanziari/contratti Fight the Stroke** |
| `edufy27` | 42 | `OneDrive-Microsoft/FY27/MicrosoftScout` → **verosimilmente Microsoft-confidential** |
| `mirrorbuddy` / `convergio` / `hve-core` / … | 4363 / 918 / 644 / … | Codice + design di prodotti propri |
| `default` | 43 | **Transcript grezzi di sessione** (contengono di tutto) |

Blast radius di un token/tunnel compromesso = **l'intera seconda memoria**, non un sotto-insieme.

### Il finding che governa tutto: `fightthestroke` è un *workspace*, non una *source*

La card `FtS-ingest.md` ingesta ~214 documenti confidenziali FtS **dentro la source `vault`**
(DoD: *"searchable in the vault"*, acceptance: *"a gbrain **vault** query returns the correct FtS doc"*),
taggati `workspace=fightthestroke`.

`workspace` è **frontmatter/metadata**, non un confine di source gbrain. Conseguenze di sicurezza:

1. **Il tag NON è un confine di sicurezza.** La ricerca semantica lavora sui chunk embedded e non
   rispetta in modo affidabile il frontmatter. "Esponi `vault` ma escludi `workspace=fightthestroke`"
   **non è enforceable** con lo strumento a disposizione.
2. **Il confine che gbrain ha davvero è la _source_.** Lo scoping avviene per `source_id`
   (verificato: parametro dello schema MCP `query`).
3. Quindi, se FtS finisce dentro `vault`, esporre `vault` = esporre i finanziari FtS. Punto.

### Il secondo finding: lo scope è *controllabile dal caller*

Dallo schema MCP `mcp__gbrain__query`, `source_id`:
> *"Pass `__all__` to span every source for trusted local callers; for remote callers `__all__` spans only your **granted sources**."*

Due implicazioni dirette:

- **Un "default pin a `vault`" NON è un confine.** Il client iPhone può passare
  `source_id=mirrorbuddy` o `__all__`. Chi ha il token sceglie la source. Pinnare un default
  è ergonomia, non sicurezza.
- **Il confine reale è la _granted-sources allowlist per-remote_** che gbrain applica ai caller
  remoti (`__all__` per un remote = solo le sue source concesse). È quello il controllo da usare,
  ed è quello che va configurato correttamente **prima** di aprire l'endpoint.

## Opzioni valutate (dai Path del design)

Assunzioni comuni: auth = bearer token nell'app Claude; nessun secondo fattore lato app;
il token vive in un device mobile (perdibile/rubabile).

### Path A — Tunnel al Mac (Tailscale *oppure* Cloudflare Tunnel)

Il design tratta A come un'opzione, ma **Tailscale e Cloudflare Tunnel hanno modelli di minaccia
opposti** e vanno separati:

| Sotto-variante | Superficie d'attacco | Token/credenziale compromessa | Chi altro può raggiungere l'host |
|---|---|---|---|
| **A1 — Tailscale (WireGuard mesh)** | **Nessuna superficie pubblica.** L'MCP è bound al tailnet; non c'è hostname pubblico da scansionare/brute-forzare. | Bearer token da solo = **inutile**: serve anche un device *dentro il tailnet* (ACL Tailscale). Difesa in profondità reale. | Solo i device del tailnet (i tuoi). ACL Tailscale restringono ulteriormente. |
| **A2 — Cloudflare Tunnel (hostname pubblico)** | **Superficie pubblica.** Hostname raggiungibile da chiunque su Internet; solo l'auth separa. Diventa un target esposto 24/7. | Leak del token *o* mis-config della Cloudflare Access policy = **accesso da qualsiasi punto del pianeta**, nessun vincolo di rete. | Chiunque su Internet che superi l'auth. |

- **A1 (Tailscale):** ✅ miglior rapporto rischio/sforzo. Nessuna esposizione pubblica, difesa in
  profondità (rete + token), ~0€, ~1h. ⚠️ il Mac deve restare acceso (non risolve "Mac spento").
- **A2 (Cloudflare):** ⚠️ esposizione pubblica per un endpoint che parla alla tua intera memoria.
  Per questa classe di dato è un downgrade di sicurezza rispetto ad A1 senza un guadagno funzionale
  che lo giustifichi. **Sconsigliato** salvo necessità specifica (es. accesso da device che non
  possono stare sul tailnet).

### Path B — Small cloud VM (~5–10€/mo)

- ✅ Risolve "Mac spento" senza hardware.
- ❌ **Downgrade di confidenzialità, borderline squalificante per FtS.** I documenti confidenziali
  FtS (finanziari/contratti) **e i loro embedding** lascerebbero fisicamente casa e vivrebbero su
  una box di terze parti. Gli embedding non sono "anonimi": sono ricostruibili/interrogabili e
  rappresentano il contenuto. Per dati FtS (e potenzialmente Microsoft-confidential in `edufy27`)
  questo confligge con il principio *local-first / review-before-backup* scritto nella stessa
  card FtS-ingest.
- ❌ Aumenta la superficie: OS della VM, patching, accesso del provider, snapshot/backup del disco.
- ⚠️ Fronte-tunnel comunque necessario (Tailscale davanti alla VM, non Postgres/MCP su IP pubblico).

### Path C — Mac mini home server

- ✅ **Local-first mantenuto** (gbrain + bge-m3 su GPU + vault restano in casa): miglior privacy,
  i dati confidenziali non lasciano l'edificio. Risolve "Mac spento" (il mini è sempre acceso).
- ⚠️ Aggiunge **superficie LAN domestica**: altri device/IoT sulla rete di casa. Va comunque
  fronteggiato con Tailscale, **mai** esposto in chiaro sulla LAN o in port-forward sul router.
- ❌ Costo hardware one-time (~500€) + un altro host da patchare e custodire fisicamente.

## Raccomandazione

**Combinazione, in fasi, con lo scoping come pre-condizione non negoziabile.**

### Mitigazioni OBBLIGATORIE prima di esporre qualsiasi endpoint (valgono per tutti i Path)

1. **Isolare FtS in una source gbrain dedicata, NON dentro `vault`.**
   Ingestare i documenti FtS in una source separata (es. `vault-fts`), così l'esclusione diventa
   *enforceable alla granularità che gbrain possiede davvero* (la source). Questo è il fix che rende
   funzionante la mitigazione "esponi solo `vault`, escludi FtS". Va fatto **cambiando la destinazione
   della card FtS-ingest** (source dedicata invece di `workspace` dentro `vault`).
2. **Sicurezza = granted-sources allowlist per-remote, non default pin.**
   Configurare il remote gbrain in *deny-by-default*: il device iPhone riceve accesso **solo** alle
   source esplicitamente concesse (es. `vault`), e **mai** a `vault-fts`, `edufy27`, `default`
   (transcript grezzi), né ai repo di codice. Verificare esplicitamente che `source_id=__all__` e
   `source_id=<qualsiasi source non concessa>` da remoto **falliscano** (test negativo, non fiducia
   nel default).
3. **Preferire Tailscale a Cloudflare Tunnel.** Nessuna esposizione pubblica; il token diventa un
   secondo fattore *de facto* dietro il confine di rete, non l'unico controllo.
4. **Bearer token trattato come segreto revocabile.** Token dedicato per device, scadenza/rotazione,
   procedura di revoca nota (device perso = revoca token + rimuovi device dal tailnet). Mai in git.
5. **Read-only + audit.** L'endpoint remoto espone solo tool di lettura/ricerca gbrain (niente
   `put_page`/`delete_page`/`schema_apply_*` da remoto). Loggare le query remote per poter rilevare
   un abuso.

### Sequenza consigliata

- **Fase 1 (adesso, se serve accesso mobile):** **Path A1 (Tailscale)** con le mitigazioni 2–5 già
  applicate. Zero costo, zero esposizione pubblica, ~1h. Copre "Mac acceso, accesso da iPhone".
  Accetta il limite: non è ancora "Mac spento".
- **Fase 2 (per il vero "Mac spento"):** **Path C (Mac mini) + Tailscale**, che mantiene local-first
  e coerenza col principio privacy della card FtS. Path B **solo** se Roberto accetta esplicitamente
  che dati FtS/edufy27 **non** siano tra le source concesse al box cloud (allora la VM ospita solo
  source non-confidenziali e il downgrade non si applica).
- **Evitare Path A2 (Cloudflare public tunnel)** salvo requisito specifico non coperto da Tailscale.

## Dipendenza esplicita con FtS-ingest — ordine

**Mettere in sicurezza l'esposizione PRIMA di ingestare i dati confidenziali FtS.** Motivazione:

- Le due card sono entrambe in `todo` e indipendenti. Se **FtS-ingest** viene eseguita prima che G5
  sia scopato in sicurezza, i finanziari/contratti FtS diventano interrogabili dall'endpoint remoto
  **nell'istante stesso** in cui l'endpoint viene aperto — senza che nessuno abbia deciso di esporli.
- È un rischio *silenzioso*: nessun errore, nessun segnale; il dato confidenziale è semplicemente
  lì, ricercabile dal telefono.

**Ordine raccomandato:**

1. Decidere G5 (questo ADR) e implementare le mitigazioni 1–2 (source `vault-fts` dedicata +
   granted-sources allowlist deny-by-default).
2. **Solo dopo**, eseguire FtS-ingest — verso la source `vault-fts` isolata, esclusa dalla grant remota.
3. Verificare con test negativo: dal telefono, una query FtS **non** deve restituire nulla.

Se Roberto preferisce fare FtS-ingest prima (es. gli serve la ricerca FtS localmente, subito):
**ammissibile**, a condizione che l'endpoint remoto G5 **resti chiuso** finché la source `vault-fts`
isolata e la allowlist non sono in atto. La regola invariante è: *nessun endpoint remoto aperto
mentre esiste una source confidenziale non isolata/non esclusa.*

## Cosa NON fare (anti-pattern)

- ❌ Affidarsi al tag `workspace=fightthestroke` come confine di accesso (non lo è).
- ❌ Affidarsi al "default source pin" come sicurezza (il caller può cambiarlo).
- ❌ Postgres o l'MCP gbrain su IP pubblico / port-forward sul router.
- ❌ Un unico token condiviso, non revocabile, committato in git o nel canone.
- ❌ Aprire l'endpoint prima di aver isolato le source confidenziali.

## Conseguenza

Il confine di accesso della memoria remota diventa **esplicito e enforceable alla granularità di
source**, deny-by-default, dietro rete privata. La memoria personale resta interrogabile dal telefono;
i dati confidenziali (FtS, edufy27, transcript grezzi) restano **fuori dal perimetro remoto** per
costruzione, non per fiducia. G5 può procedere quando Roberto decide spesa e Path; questo ADR fissa
le condizioni di sicurezza che quella decisione deve rispettare.
