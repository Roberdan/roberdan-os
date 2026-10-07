#!/usr/bin/env bash
# gbrain health needs a source-owned positive control and a negative control.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
ok() { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/repo"
printf 'source-fixture\n' > "$TMP/repo/.gbrain-source"

cat > "$TMP/bin/gbrain" <<'SH'
#!/usr/bin/env bash
symbol="${2:-}"
case "${GBRAIN_STUB_MODE:-healthy}:$symbol" in
  healthy:KnownCanary) printf '{"count":2}\n' ;;
  healthy:__rda_gbrain_negative_control_9f4c0e__) printf '{"count":0}\n' ;;
  missing:*) printf '{"count":0}\n' ;;
  false-negative:KnownCanary) printf '{"count":1}\n' ;;
  false-negative:__rda_gbrain_negative_control_9f4c0e__) printf '{"count":1}\n' ;;
  malformed:*) printf 'not-json\n' ;;
  *) printf '{"count":0}\n' ;;
esac
SH
chmod +x "$TMP/bin/gbrain"

run_doctor() {
  (
    cd "$TMP/repo" || exit 1
    HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" \
      GBRAIN_STUB_MODE="$1" bash "$ROOT/bin/toolchain-doctor.sh" --json ${2:+--symbol "$2"}
  )
}

status_for() {
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["status"] for x in d["checks"] if x["name"]=="gbrain-symbols"))'
}

healthy="$(run_doctor healthy KnownCanary)"
[ "$(printf '%s' "$healthy" | status_for)" = ok ] \
  && ok "known positive + absent negative control => ok" \
  || err "healthy controls did not return ok: $healthy"

missing="$(run_doctor missing KnownCanary)"
[ "$(printf '%s' "$missing" | status_for)" = broken ] \
  && ok "missing known positive with clean negative => broken" \
  || err "missing canary did not return broken: $missing"

bad_negative="$(run_doctor false-negative KnownCanary)"
[ "$(printf '%s' "$bad_negative" | status_for)" = inconclusive ] \
  && ok "negative control resolving => inconclusive" \
  || err "false negative control was not inconclusive: $bad_negative"

malformed="$(run_doctor malformed KnownCanary)"
[ "$(printf '%s' "$malformed" | status_for)" = inconclusive ] \
  && ok "malformed command output => inconclusive" \
  || err "malformed output was not inconclusive: $malformed"

no_canary="$(run_doctor healthy "")"
[ "$(printf '%s' "$no_canary" | status_for)" = inconclusive ] \
  && ok "no source-owned canary => inconclusive, not broken" \
  || err "missing canary was not inconclusive: $no_canary"

[ "$FAIL" -eq 0 ] && { echo "test-toolchain-doctor: PASS"; exit 0; }
echo "test-toolchain-doctor: FAIL"
exit 1
