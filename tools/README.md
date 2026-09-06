# tools — strumenti locali per il Mac

Piccoli strumenti che servono a Roberto tutti i giorni, non legati a un singolo
progetto. Girano **solo su questo Mac**: niente rete, niente account.

## Installazione

```sh
./tools/installa.sh
```

Collega i comandi in `~/.local/bin`, compila il notificatore, installa l'azione
rapida del Finder e aggiunge l'alias in `~/.zshrc`. Si può rilanciare quante
volte si vuole.

Serve Ghostscript (`brew install ghostscript`) e gli strumenti di Xcode.

## comprimi-pdf

Comprime un PDF come fa Acrobat, con Ghostscript. Il risultato resta **accanto
all'originale**, con «compressed» aggiunto al nome; l'originale non si tocca mai.
Se il risultato venisse più grande, viene scartato.

```sh
comprimi-pdf documento.pdf                 # qualità «ebook», la migliore di media
comprimi-pdf -q schermo documento.pdf      # più piccolo, qualità inferiore
comprimi-pdf -q stampa documento.pdf       # per la stampa
comprimi-pdf --avvisa documento.pdf        # con notifiche di inizio e fine
```

Su documenti scansionati la riduzione tipica è del 90-95% (misurato: 24,7 MB →
1,75 MB e 237,5 MB → 16,3 MB, pagine intatte).

Nel Finder: tasto destro su uno o più PDF → **Azioni rapide → Comprimi PDF**.
Un file grosso può richiedere minuti; le notifiche dicono quando è finita.

## avvisa

Notificatore proprio. Serve perché `osascript display notification` viene
attribuito a «Editor di script», e cliccando la notifica si apriva quella
finestra senza senso. Questa invece si presenta col suo nome e, al clic, mostra
il file nel Finder.

```sh
avvisa --titolo "Fatto" --testo "Il file è pronto." --apri /percorso/file.pdf --suono
```

## Cose imparate, da non riscoprire

- La chiave che manda un comando fra le **Azioni rapide** del Finder invece che
  sotto «Servizi» è `NSIconName` nell'`Info.plist` del workflow.
- Il pannello «Estensioni Finder» delle Impostazioni di Sistema **non elenca** i
  workflow di Automator: si attivano da `pbs.plist`.
- L'icona va disegnata a **pixel esatti**: lasciando fare a `NSImage`, su uno
  schermo Retina esce al doppio e `iconutil` scarta le misure piccole.
- Gli identificatori dei bundle sono **insensibili alle maiuscole**: cambiare
  solo `avvisa` in `Avvisa` non produce una registrazione nuova.
- Le notifiche di un'app appena creata possono arrivare con **minuti** di
  ritardo alla prima registrazione: non concludere «non funziona» dopo tre
  secondi.
