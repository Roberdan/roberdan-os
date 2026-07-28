#!/usr/bin/env bash
# test/test-bus-mcp.sh — proves the typed MCP surface is a NARROWING of the bus.
#
# The claim under test is not "the bus is safe". It is narrower and checkable:
# an agent reaching the bus through bus-mcp.py cannot express anything except a
# message. The evasions that defeated eight rounds of textual checks all worked
# by smuggling shell syntax through a string that something later interpreted;
# here they are asserted to arrive as inert DATA, because no interpreter is left
# on the path.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()      { printf "  ok: %s\n" "$1"; }

command -v python3 >/dev/null 2>&1 || { printf "  skip: python3 not present\n"; exit 0; }
command -v jq      >/dev/null 2>&1 || { printf "  skip: jq not present\n"; exit 0; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rda-bus-mcp.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

# Fully isolated store: this test must never read or write the real thread log.
export RDA_HOME="$TMP/home"
export RDA_BUS_HOME="$TMP/home/bus"
mkdir -p "$RDA_BUS_HOME"

# Both checks below read the file as CODE, not as text. Grepping the source
# would flag the paragraph at the top that explains there is no shell here, and
# - far worse - would let a real shell call hide behind a carefully worded
# comment. ast.unparse re-emits the parsed tree, so comments and docstrings are
# gone by construction and what is left is only what Python will actually run.
_code_only() {
  python3 - "$1" <<'PYEOF'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
for node in ast.walk(tree):
    if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
        body = getattr(node, "body", [])
        if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) \
           and isinstance(body[0].value.value, str):
            body.pop(0)   # drop the docstring: prose, not behaviour
print(ast.unparse(tree))
PYEOF
}

MCP="bus/bus-mcp.py"
REPO="testrepo"
CARD="260101-000000"

# Roles must exist in bus/roles/ for _assert_role to pass; use two real ones.
ROLE_A="$(basename "$(find bus/roles -maxdepth 1 -name '*.json' | LC_ALL=C sort | head -1)" .json 2>/dev/null)"
ROLE_B="$(basename "$(find bus/roles -maxdepth 1 -name '*.json' | LC_ALL=C sort | sed -n 2p)" .json 2>/dev/null)"
[ -n "$ROLE_A" ] && [ -n "$ROLE_B" ] || { printf "  skip: no roles registered\n"; exit 0; }

# rpc <<<'json' -> one response line
rpc() { python3 "$MCP" 2>/dev/null; }

# --- 1. the registry is closed ---------------------------------------------
section "the tool registry is CLOSED (an unknown name is refused, not interpreted)"
out="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"bus_exec","arguments":{}}}' | rpc)"
if printf '%s' "$out" | jq -e '.error.message | test("unknown tool")' >/dev/null 2>&1; then
  ok "an unregistered tool name is an error, never a dispatch"
else
  err "an unknown tool name was not refused: $out"
fi

section "the advertised surface is exactly send/read/peek/log — no close, no open, no roles"
names="$(printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | rpc | jq -r '.result.tools[].name' | LC_ALL=C sort | tr '\n' ' ')"
if [ "$names" = "bus_log bus_peek bus_read bus_send " ]; then
  ok "surface is exactly: $names"
else
  err "unexpected tool surface: '$names'"
fi

# --- 2. a normal message still works ---------------------------------------
section "a well-formed message is appended and read back verbatim"
BODY='Ho misurato: 289s in sequenza, 47s in parallelo. Il costo era l ordine.'
req="$(jq -nc --arg r "$REPO" --arg c "$CARD" --arg f "$ROLE_A" --arg t "$ROLE_B" --arg b "$BODY" \
  '{jsonrpc:"2.0",id:3,method:"tools/call",params:{name:"bus_send",arguments:{repo:$r,card:$c,from_role:$f,to_role:$t,kind:"note",body:$b}}}')"
out="$(printf '%s\n' "$req" | rpc)"
if printf '%s' "$out" | jq -e '.result.isError != true' >/dev/null 2>&1; then
  ok "send accepted"
else
  err "send of a legitimate message failed: $(printf '%s' "$out" | jq -r '.result.content[0].text // .')"
fi

log="$RDA_BUS_HOME/$REPO/$CARD.jsonl"
if [ -f "$log" ] && [ "$(jq -r '.body' < "$log" | head -1)" = "$BODY" ]; then
  ok "the body survived verbatim into the store"
else
  err "the body did not round-trip into $log"
fi

if [ "$(jq -r '.from' < "$log" | head -1)" = "$ROLE_A" ]; then
  ok "attribution is preserved"
else
  err "attribution lost"
fi

# --- 3. shell metacharacters are DATA --------------------------------------
# Each of these defeated a textual check in an earlier round. Through a typed
# argv there is nothing left to interpret them, so the requirement is that they
# land in the log byte-for-byte and that nothing runs.
section "shell metacharacters in a body are stored, never interpreted"
CANARY="$TMP/canary"
EVIL='$(touch '"$CANARY"'-a); `touch '"$CANARY"'-b`; $(git -c alias.z="!touch '"$CANARY"'-c" z)'
req="$(jq -nc --arg r "$REPO" --arg c "$CARD" --arg f "$ROLE_A" --arg t "$ROLE_B" --arg b "$EVIL" \
  '{jsonrpc:"2.0",id:4,method:"tools/call",params:{name:"bus_send",arguments:{repo:$r,card:$c,from_role:$f,to_role:$t,kind:"note",body:$b}}}')"
printf '%s\n' "$req" | rpc >/dev/null

if [ ! -e "$CANARY-a" ] && [ ! -e "$CANARY-b" ] && [ ! -e "$CANARY-c" ]; then
  ok "no command substitution, no backtick, no git-alias evasion executed"
else
  err "a body executed something: $(ls "$TMP" | tr '\n' ' ')"
fi

stored="$(jq -r 'select(.kind=="note") | .body' < "$log" | tail -1)"
if [ "$stored" = "$EVIL" ]; then
  ok "the hostile body is stored byte-for-byte as inert text"
else
  err "the hostile body was altered in flight"
fi

# --- 4. typed arguments are validated BEFORE any process starts -------------
section "argument grammar refuses traversal and flag-injection before dispatch"
for bad_repo in '../../etc' 'a/b' '--from' ''; do
  req="$(jq -nc --arg r "$bad_repo" --arg c "$CARD" --arg f "$ROLE_A" --arg t "$ROLE_B" \
    '{jsonrpc:"2.0",id:5,method:"tools/call",params:{name:"bus_send",arguments:{repo:$r,card:$c,from_role:$f,to_role:$t,kind:"note",body:"x"}}}')"
  out="$(printf '%s\n' "$req" | rpc)"
  msg="$(printf '%s' "$out" | jq -r '.result.content[0].text // ""')"
  # Asserting only "it was refused" would pass even with this layer's validation
  # deleted, because bus.sh validates again downstream - a mutation proved it.
  # The claim here is that the refusal happens BEFORE a process starts, so the
  # test matches THIS layer's wording ("repo:"), not bus.sh's ("--repo:").
  if printf '%s' "$out" | jq -e '.result.isError == true' >/dev/null 2>&1 \
     && printf '%s' "$msg" | grep -qE '^repo: '; then
    ok "refused locally, before dispatch: repo=$(printf '%q' "$bad_repo")"
  else
    err "illegal repo not refused by this layer: $(printf '%q' "$bad_repo") -> $msg"
  fi
done

section "kind is a closed enum"
req="$(jq -nc --arg r "$REPO" --arg c "$CARD" --arg f "$ROLE_A" --arg t "$ROLE_B" \
  '{jsonrpc:"2.0",id:6,method:"tools/call",params:{name:"bus_send",arguments:{repo:$r,card:$c,from_role:$f,to_role:$t,kind:"dispatch",body:"x"}}}')"
out="$(printf '%s\n' "$req" | rpc)"
msg="$(printf '%s' "$out" | jq -r '.result.content[0].text // ""')"
# Same reasoning as the repo grammar above: match this layer's wording, so
# deleting the local enum check cannot be hidden by bus.sh refusing later.
if printf '%s' "$out" | jq -e '.result.isError == true' >/dev/null 2>&1 \
   && printf '%s' "$msg" | grep -qE '^kind: must be one of '; then
  ok "an unlisted kind ('dispatch') is refused locally, before dispatch"
else
  err "an unlisted kind was not refused by this layer -> $msg"
fi

section "an empty body is refused rather than stored"
req="$(jq -nc --arg r "$REPO" --arg c "$CARD" --arg f "$ROLE_A" --arg t "$ROLE_B" \
  '{jsonrpc:"2.0",id:7,method:"tools/call",params:{name:"bus_send",arguments:{repo:$r,card:$c,from_role:$f,to_role:$t,kind:"note",body:"   "}}}')"
out="$(printf '%s\n' "$req" | rpc)"
if printf '%s' "$out" | jq -e '.result.isError == true' >/dev/null 2>&1; then
  ok "a whitespace-only body is refused"
else
  err "a whitespace-only body was stored"
fi

section "a citation must look like a citation"
req="$(jq -nc --arg r "$REPO" --arg c "$CARD" --arg f "$ROLE_A" --arg t "$ROLE_B" \
  '{jsonrpc:"2.0",id:8,method:"tools/call",params:{name:"bus_send",arguments:{repo:$r,card:$c,from_role:$f,to_role:$t,kind:"note",body:"x",ref:"; rm -rf /"}}}')"
out="$(printf '%s\n' "$req" | rpc)"
if printf '%s' "$out" | jq -e '.result.isError == true' >/dev/null 2>&1; then
  ok "a free-form ref is refused"
else
  err "a free-form ref was accepted"
fi

# --- 5. the surface cannot mutate kanban state ------------------------------
# Property 2 is Roberto's approval gate. The MCP layer must not offer a way in.
section "no tool on this surface can move a card (property 2, the human gate)"
# Grepping for the word "kanban" was the first version of this check and it was
# wrong: the only occurrences are tool DESCRIPTIONS stating that kanban state is
# not touched, so the check failed on the file promising the very property it was
# meant to verify. The property that actually matters is narrower and structural:
# which VERBS can ever be dispatched. Every one is a literal in the argv list
# handed to _run_bus, so the AST can enumerate them exhaustively.
verbs="$(python3 - bus/bus-mcp.py <<'PYEOF'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
found, dynamic = set(), False
for node in ast.walk(tree):
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "_run_bus":
        if not node.args:
            dynamic = True; continue
        arg = node.args[0]
        if isinstance(arg, ast.List) and arg.elts:
            head = arg.elts[0]
            if isinstance(head, ast.Constant) and isinstance(head.value, str):
                found.add(head.value)
            else:
                dynamic = True          # a computed verb is an open surface
        elif isinstance(arg, ast.Name):
            # argv built earlier in the function: resolve its literal head.
            fn = None
            for f in ast.walk(tree):
                if isinstance(f, ast.FunctionDef) and node in list(ast.walk(f)):
                    fn = f; break
            resolved = False
            for a in ast.walk(fn) if fn else []:
                if isinstance(a, ast.Assign) and any(
                    isinstance(t, ast.Name) and t.id == arg.id for t in a.targets
                ) and isinstance(a.value, ast.List) and a.value.elts:
                    head = a.value.elts[0]
                    if isinstance(head, ast.Constant) and isinstance(head.value, str):
                        found.add(head.value); resolved = True
            dynamic = dynamic or not resolved
        else:
            dynamic = True
print("DYNAMIC" if dynamic else " ".join(sorted(found)))
PYEOF
)"
if [ "$verbs" = "log read send" ]; then
  ok "the only dispatchable verbs are exactly: $verbs (no kb, no close, no open)"
else
  err "unexpected dispatch surface: '$verbs' (expected 'log read send')"
fi

# --- 6. the file itself cannot reach a shell --------------------------------
section "the implementation contains no shell-invoking construct"
if _code_only bus/bus-mcp.py | grep -nE 'shell=True|os\.system|os\.popen|subprocess\.getoutput|\beval\(|\bexec\('; then
  err "a shell-invoking construct is present in executable code"
else
  ok "no shell=True, os.system, os.popen, eval or exec in executable code"
fi

section "exactly one executable is reachable, resolved by path and not by PATH"
count="$(grep -cE 'subprocess\.run' bus/bus-mcp.py)"
if [ "$count" -eq 1 ] && grep -q 'BUS_SH = os.path.join' bus/bus-mcp.py; then
  ok "a single subprocess.run, dispatching a path-resolved bus.sh"
else
  err "expected exactly one subprocess.run against a path-resolved bus.sh (found $count)"
fi

printf "\n"
[ "$FAIL" -eq 0 ] && echo "test-bus-mcp: PASS" || echo "test-bus-mcp: FAIL"
exit "$FAIL"
