#!/usr/bin/env bash
# test/test-vm-sweep.sh — vm-sweep.sh vede le istanze Colima ferme, non tocca mai quelle in
# esecuzione o quelle sotto soglia, e cancella solo con --yes. Stub di `colima`/`limactl`:
# creare una VM vera per un test costerebbe esattamente il problema che questo file previene.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM="$ROOT/kanban/vm-sweep.sh"
FAILS=0
ok()   { printf '  ok   — %s\n' "$1"; }
fail() { printf '  FAIL — %s\n' "$1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export PATH="$TMP/bin:$PATH"; mkdir -p "$TMP/bin"

# Due profili fermi (uno vecchio, rimovibile; uno recente, sotto soglia) e uno in esecuzione:
# nessuno dei tre e' una VM vera, solo cartelle con la data che serve al test.
mkdir -p "$HOME/.colima/vecchio" "$HOME/.colima/recente" "$HOME/.colima/attivo" \
         "$HOME/.colima/_lima/_disks/colima-vecchio"
touch -t 202501010000 "$HOME/.colima/vecchio"
touch -t 202501010000 "$HOME/.colima/_lima/_disks/colima-vecchio"
# "recente": adesso, quindi sotto qualunque soglia >0 giorni
touch "$HOME/.colima/recente"
touch "$HOME/.colima/attivo"
DELETED_MARK="$TMP/deleted"

cat > "$TMP/bin/colima" <<EOF
#!/bin/sh
case "\$1" in
  list)
    printf 'PROFILE   STATUS     ARCH       CPUS    MEMORY    DISK     RUNTIME    ADDRESS\n'
    printf 'vecchio   Stopped    aarch64    2       4GiB      20GiB    docker\n'
    printf 'recente   Stopped    aarch64    2       4GiB      1GiB     docker\n'
    printf 'attivo    Running    aarch64    2       4GiB      1GiB     docker\n'
    ;;
  delete)
    echo "\$2" >> "$DELETED_MARK"
    ;;
esac
EOF
chmod +x "$TMP/bin/colima"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/limactl"; chmod +x "$TMP/bin/limactl"

# --- report, senza --yes: non deve toccare niente ------------------------------------------
out="$(bash "$VM" sweep --stale-days 3 2>&1)"
case "$out" in *"rimovibile: vecchio"*) ok "vede il profilo vecchio come rimovibile" ;; *) fail "non vede il profilo vecchio ($out)" ;; esac
case "$out" in *"sotto soglia"*"recente"*) ok "tiene il profilo recente sotto soglia" ;; *) fail "non protegge il profilo recente ($out)" ;; esac
case "$out" in *"non si tocca: attivo"*) ok "dichiara intoccabile il profilo in esecuzione" ;; *) fail "non protegge il profilo in esecuzione ($out)" ;; esac
[ -f "$DELETED_MARK" ] && fail "senza --yes ha gia' cancellato qualcosa" || ok "senza --yes non cancella niente"
case "$out" in *"kb checkup --yes"*) ok "indica come applicare la pulizia" ;; *) fail "non indica come applicare" ;; esac

# --- --yes: solo il vecchio sparisce -------------------------------------------------------
out2="$(bash "$VM" sweep --yes --stale-days 3 2>&1)"
[ -f "$DELETED_MARK" ] && grep -q '^vecchio$' "$DELETED_MARK" && ok "--yes cancella il profilo vecchio" || fail "--yes non ha cancellato il profilo vecchio"
grep -q '^recente$' "$DELETED_MARK" 2>/dev/null && fail "--yes ha cancellato il profilo recente" || ok "--yes non tocca il profilo recente"
grep -q '^attivo$' "$DELETED_MARK" 2>/dev/null && fail "--yes ha cancellato il profilo in esecuzione" || ok "--yes non tocca mai il profilo in esecuzione"
case "$out2" in *"liberati"*) ok "riporta lo spazio liberato" ;; *) fail "non riporta lo spazio liberato" ;; esac

# --- colima non installato: niente errori, referto onesto ----------------------------------
out3="$(PATH="/usr/bin:/bin" bash "$VM" sweep 2>&1)"
case "$out3" in *"non installato"*) ok "senza colima installato lo dice, senza errori" ;; *) fail "senza colima non gestisce l'assenza ($out3)" ;; esac

case "$out$out2$out3" in *"unbound variable"*) fail "muore con un errore di shell" ;; *) ok "nessun errore di shell" ;; esac

if [ "$FAILS" -eq 0 ]; then
  echo "test-vm-sweep: ✅ ALL GREEN"
else
  echo "--- referto (report) ---"; printf '%s\n' "$out"
  echo "--- referto (--yes) ---"; printf '%s\n' "$out2"
  echo "test-vm-sweep: ❌ $FAILS FAIL"; exit 1
fi
