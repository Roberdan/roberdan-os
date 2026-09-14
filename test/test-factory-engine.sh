#!/usr/bin/env bash
# test-factory-engine.sh — Roberto's directive, 2026-09-13: unattended work must never spend
# the Claude budget. The factory therefore runs on GitHub Copilot CLI by default and reaches
# `claude` only when someone writes RDA_FACTORY_ENGINE=claude on purpose.
# A promise nobody can check is worth nothing, so what is asserted here is the observable
# fact: with no environment set, a stub `claude` on PATH is NEVER executed, and the command
# line the factory builds is Copilot's, with its native deny list attached.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
ok()  { printf '  ok   — %s\n' "$1"; }
err() { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

TMP="$(mktemp -d)"; trap '/bin/rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/dir"
# Stubs that record WHICH binary ran and with what argv. A run that touches the claude stub
# leaves a file behind — that file existing is the whole failure mode this test exists for.
for b in claude copilot; do
  printf '#!/usr/bin/env bash\ntouch "%s/ran-%s"\nprintf "%%s\\n" "$@" > "%s/argv-%s"\nprintf "%%s" "${RDA_HEADLESS:-}" > "%s/headless-%s"\n' "$TMP" "$b" "$TMP" "$b" "$TMP" "$b" > "$TMP/bin/$b"
  chmod +x "$TMP/bin/$b"
done

launch() { # $1 = engine env value ("" = unset), $2 = model alias
  /bin/rm -f "$TMP"/ran-* "$TMP"/argv-*
  if [ -n "$1" ]; then export RDA_FACTORY_ENGINE="$1"; else unset RDA_FACTORY_ENGINE; fi
  PATH="$TMP/bin:$PATH" bash -c '
    source "$1/factory/lib.sh"; TIMEOUT_BIN=""
    launch_agent "probe prompt" "$3" "$2" 30 "$2/log"' _ "$ROOT" "$TMP/dir" "$2" >/dev/null 2>&1
  unset RDA_FACTORY_ENGINE
}
argv_of() { tr '\n' ' ' < "$TMP/argv-$1" 2>/dev/null; }

echo "=== default: Copilot, and the Claude budget is never touched ==="
launch "" sonnet
[ -e "$TMP/ran-copilot" ] && ok "no env set -> the copilot binary ran" || err "no env set -> copilot did NOT run"
[ ! -e "$TMP/ran-claude" ] && ok "no env set -> the claude binary was never executed" \
  || err "THE CLAUDE BINARY RAN BY DEFAULT — the directive is broken"
engine="$(bash -c 'unset RDA_FACTORY_ENGINE; source "$1/factory/lib.sh"; printf %s "$FACTORY_ENGINE"' _ "$ROOT")"
[ "$engine" = "copilot" ] && ok "FACTORY_ENGINE defaults to copilot" || err "FACTORY_ENGINE defaults to '$engine'"

echo "=== the Copilot command line ==="
a="$(argv_of copilot)"
case "$a" in *"--allow-all-tools"*) ok "--allow-all-tools (required for non-interactive mode)" ;;
  *) err "no --allow-all-tools — a headless copilot run would stall on a prompt" ;; esac
case "$a" in *"--deny-tool shell(git push)"*) ok "--deny-tool shell(git push) is attached" ;;
  *) err "the deny list is missing from the command line: $a" ;; esac
for t in 'shell(git commit --amend)' 'shell(git rebase)' 'shell(git reset --hard)' 'shell(rm -rf)' 'shell(gh pr merge)' 'shell(gh release)'; do
  case "$a" in *"--deny-tool $t"*) ok "denied: $t" ;; *) err "NOT denied: $t" ;; esac
done
case "$a" in *"--model claude-sonnet-5"*) ok "alias sonnet -> claude-sonnet-5 (mid class, registry id)" ;;
  *) err "sonnet did not resolve to a Copilot model id: $a" ;; esac
case "$a" in *"--add-dir $TMP/dir"*) ok "the task dir is passed with --add-dir" ;;
  *) err "no --add-dir: the agent would be scoped to the wrong tree" ;; esac
launch "" opus
case "$(argv_of copilot)" in *"--model claude-opus-5"*) ok "alias opus -> claude-opus-5" ;;
  *) err "opus did not resolve to a Copilot frontier id" ;; esac

[ "$(cat "$TMP/headless-copilot" 2>/dev/null)" = "1" ] && ok "the headless agent runs with RDA_HEADLESS=1 (never re-photographs or chases the queue)" \
  || err "RDA_HEADLESS=1 not passed: a factory/@thor run gets pushed into the authorized queue"

echo "=== claude only on an explicit opt-in ==="
launch claude sonnet
[ -e "$TMP/ran-claude" ] && ok "RDA_FACTORY_ENGINE=claude -> the claude binary ran" || err "explicit claude opt-in did not reach claude"
[ ! -e "$TMP/ran-copilot" ] && ok "...and copilot did not" || err "both engines ran"
a="$(argv_of claude)"
case "$a" in *"--permission-prompts none"*) ok "claude engine keeps --permission-prompts none" ;;
  *) err "claude engine lost its permission flags: $a" ;; esac
case "$a" in *"--model sonnet"*) ok "claude engine keeps the tier alias as the model" ;;
  *) err "claude engine model is wrong: $a" ;; esac
case "$a" in *"--dangerously-skip-permissions"*) err "the old blanket-permission flag is BACK" ;;
  *) ok "no --dangerously-skip-permissions anywhere on the command line" ;; esac

echo "=== an unknown engine stops the factory, it does not guess ==="
out="$(RDA_FACTORY_ENGINE=gemini bash -c 'source "$1/factory/lib.sh"; factory_engine_bin' _ "$ROOT" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'unknown RDA_FACTORY_ENGINE' \
  && ok "RDA_FACTORY_ENGINE=gemini -> refused, no silent fallback" \
  || err "an unknown engine did not fail (rc=$rc, out=$out)"

echo "=== no factory script spends Claude by accident ==="
stray="$(grep -rn -- '"\$CLAUDE" -p \|claude -p ' "$ROOT"/factory/*.sh | grep -v 'launch_agent\|^.*#' || true)"
[ -z "$stray" ] && ok "no factory script launches claude outside launch_agent" \
  || err "a factory script starts claude directly: $stray"

printf '\n'
[ "$fails" -eq 0 ] && { echo "test-factory-engine: ✅ ALL GREEN"; exit 0; }
echo "test-factory-engine: ❌ $fails FAIL"; exit 1
