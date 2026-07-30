#!/usr/bin/env bash
# precheck.sh — le tre domande da fare a una card PRIMA di eseguirla.
#
# PERCHE' ESISTE. Il 2026-07-30, in un giorno solo, cinque card si sono rivelate sbagliate nel
# momento in cui qualcuno le ha prese in mano:
#
#   1. MCAPS: il lavoro era gia' stato fatto il giorno 11 e reso inutile da una decisione del
#      giorno 13. La card e' rimasta aperta VENTI giorni.
#   2. "Le due slide": la sua acceptance chiedeva cio' che le sue card sorelle dovevano fare.
#   3. Identita' reali nel codice: due card per lo stesso problema.
#   4. gbrain coda bloccata: due criteri su cinque erano il contenuto delle altre due card gbrain.
#   5. Casa Martucci: quattro card sullo stesso lavoro, aperte in tre giorni.
#
# I freni scritti quel mattino fermano la NASCITA delle card e ne limitano il numero in corso.
# Nessuno guarda una card nel momento in cui la prendi in mano — che e' l'unico momento in cui
# le domande "serve ancora? la sta gia' facendo qualcun altro? e' gia' stata fatta?" hanno senso.
#
# Una card e' la fotografia di un problema NEL GIORNO in cui e' stata scritta. Piu' invecchia,
# meno assomiglia al presente, e la pila non ha memoria di questo.
#
# NON BLOCCA, di proposito. Un gate che blocca su un sospetto statistico verrebbe aggirato al
# terzo falso allarme. Stampa gli avvisi E LI SCRIVE SULLA CARD, cosi' chi ci lavora se li trova
# davanti invece di scoprirli dopo tre ore.

# Parole troppo comuni per dire qualcosa: se due card condividono "the" non si somigliano.
_pc_stopwords=" the and for with from that this into della delle degli dello sulla sulle nella
nelle come dove quando perche' anche solo ogni tutti tutte tutto card repo test tests file files
work lavoro fare done fatto piu' non che con per una uno gli del dei alla alle sono stato stata "

# _pc_parole <file> — le parole significative di titolo + definizione di fatto.
# Minimo 5 caratteri: sotto quella soglia le collisioni casuali superano i veri accostamenti.
_pc_parole() {
  { _field "$1" title; _field "$1" dod; } 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9àèéìòù' '\n' \
    | awk 'length($0) >= 5' \
    | while read -r w; do case "$_pc_stopwords" in *" $w "*) ;; *) echo "$w" ;; esac; done \
    | sort -u
}

# _pc_comuni <fileA> <fileB> — quante parole significative condividono.
_pc_comuni() {
  comm -12 <(_pc_parole "$1") <(_pc_parole "$2") 2>/dev/null | wc -l | tr -d ' '
}

# _pc_giorni <file> — eta' della card in giorni, dal campo created:.
_pc_giorni() {
  local c; c="$(_field "$1" created)"
  [ -n "$c" ] || { echo 0; return; }
  local e; e="$(date -j -f '%Y-%m-%d' "$c" +%s 2>/dev/null || date -d "$c" +%s 2>/dev/null || echo '')"
  [ -n "$e" ] || { echo 0; return; }
  echo $(( ( $(date +%s) - e ) / 86400 ))
}

# precheck <card-file> — stampa gli avvisi e li restituisce, uno per riga, per la card.
precheck() {
  local f="$1" avvisi="" id; id="$(basename "$f" .md)"
  local soglia="${RDA_PRECHECK_SOGLIA:-2}"   # parole in comune oltre le quali si segnala

  # 1. ETA'. Il caso MCAPS: venti giorni fra "l'ho aperta" e "la eseguo", e nel mezzo il mondo
  #    era cambiato due volte. Sette giorni e' una settimana lavorativa: oltre, si rilegge.
  local g; g="$(_pc_giorni "$f")"
  if [ "$g" -gt 7 ]; then
    avvisi="${avvisi}ETA': questa card ha $g giorni. Rileggila prima di eseguirla: e' la fotografia di un problema di allora, non di oggi.
"
  fi

  # 2. SOVRAPPOSIZIONI fra card ancora aperte. Il caso "le due slide" e il caso gbrain: una card
  #    che chiede cio' che un'altra deve fare non si chiude mai, perche' aspetta se stessa.
  local altra n
  for altra in "$KB/todo"/*.md "$KB/doing"/*.md; do
    [ -e "$altra" ] || continue
    [ "$altra" = "$f" ] && continue
    case "$(basename "$altra")" in _*) continue ;; esac
    n="$(_pc_comuni "$f" "$altra")"
    if [ "$n" -ge "$soglia" ]; then
      avvisi="${avvisi}SOVRAPPOSIZIONE ($n parole in comune) con $(basename "$altra" .md), ancora aperta: $(_field "$altra" title)
"
    fi
  done

  # 3. FORSE E' GIA' STATA FATTA. Il caso MCAPS in pieno: il lavoro era in un commit di nove
  #    giorni prima. Si guardano le 30 card chiuse piu' recenti — oltre, il rumore supera il
  #    segnale e il controllo diventa lento su un archivio che cresce senza limite.
  local recenti
  recenti="$(ls -t "$KB/done"/*.md 2>/dev/null | head -30)"
  for altra in $recenti; do
    [ -e "$altra" ] || continue
    n="$(_pc_comuni "$f" "$altra")"
    if [ "$n" -ge "$soglia" ]; then
      avvisi="${avvisi}FORSE GIA' FATTA ($n parole in comune): $(basename "$altra" .md) e' CHIUSA e dice: $(_field "$altra" title)
"
    fi
  done

  printf '%s' "$avvisi"
}
