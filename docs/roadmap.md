# Ordine di lavoro — roberdan-os

**Questo file non aggiunge requisiti: ordina card che esistono già.** Ogni riga è un `id` del
board. Nessuna clausola nuova, quindi niente da coprire e nessun gate da aggirare.

Regola in vigore dal 2026-07-30: **una card in corso per progetto**. Si prende la prima non
chiusa, si finisce, si passa alla successiva.

Ultimo rilascio stabile: **`v2.21.0`** (CI verde su `main`, `validate.sh` ALL GREEN).

**Priorità dichiarata**: roberdan-os viene **dopo** VirtualBPMFy27. Il 2026-07-30 il sistema
stava lavorando su se stesso mentre il progetto vero aveva zero card in corso e diciannove in
coda; il budget delle meta-card esiste per questo. Le due card qui sotto si fanno quando
VirtualBPM non ha niente di aperto, non "quando capita".

---

## 1º — Le due già pronte a partire

| id | Cosa | Perché prima |
|---|---|---|
| `260725-185802` | Guardia progressiva sui file oltre 300 righe | È un ratchet, come quello scritto oggi per l'acceptance: non rompe i file esistenti, impedisce i nuovi. |
| `260725-185833` | Rendere Edge obbligatorio per l'automazione Playwright | Già scelto nel canone (`rules/best-practices.md § Execution Defaults`), manca solo il controllo meccanico. |

## 2º — La dieta, quel che resta

Non sono card: sono le due voci di `docs/findings.md` che valgono una promozione appena
qualcuno le guarda.

| Cosa | Da findings |
|---|---|
| `evolve/watch.sh` deve scrivere **un riassunto**, non 5 card vuote | è **spento** dal 2026-07-30, quindi non fa danno mentre aspetta |
| `kb finish` dichiara "verified by @thor" anche quando non è vero | va preso `--by` come dato, non presupposto |
| L'installer dei hook lanciato da un worktree incide il percorso del worktree | quarta istanza della stessa famiglia; si blocca ad alta voce, quindi non passa niente senza controllo |

## 3º — Altri progetti che vivono su questo board

Fermi per scelta, non per dimenticanza. Li elenco perché "non lo sapevo" non sia una scusa.

| id | Progetto | Cosa |
|---|---|---|
| `260730-095540` | gbrain | in corso: coda job sbloccata, restano due interruttori di Roberto (chiave, GPU) |
| `260730-102955` | gbrain | chunker a 2000 token contro `ubatch` 2048 di ollama: nessun margine |
| `260730-102956-1` | gbrain | il punteggio del cervello penalizza un cervello di codice |
| `260730-102956` | gbrain | cicli completi sulle 12 sorgenti rimanenti (ore di GPU) |
| `260709-114214` | MirrorHR | segnali aggiuntivi (accelerometro/EDA) — **gate umano** |
| `260713-093430` | MirrorHR | P1 Safety Recovery, da T8 |
| `260710-113149` | personal | azioni urgenti di compliance MCAPS — **in corso da 20 giorni, zero commit**: bloccata o morta? |

---

## Cosa aspetta Roberto, e nient'altro

1. **Il ticket a GitHub Support** per roberdan-os → testo pronto in `~/Desktop/TICKET-GITHUB-SUPPORT.md`.
   Finché non parte, i vecchi commit riscritti restano leggibili per codice.
2. **`MirrorBuddy`** (pubblico) ha 5 indirizzi aziendali nella storia, uno dei quali sembra una
   persona reale che non è lui. Decisione sua: sostituire il nome nell'albero attuale (consigliato)
   o riscrivere anche quella storia.
3. **Due interruttori di gbrain**: la chiave `ZEROENTROPY_API_KEY`, e le ore di GPU per i cicli.
