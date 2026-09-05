#!/usr/bin/env bash
# test-model-registry.sh — the model registry, the resolver, the launcher and the generated
# Copilot artifacts, pinned.
#
# WHY IT EXISTS. Until 2026-09-05 the tier -> id map was an 18-line `case` inside bin/sync.sh
# and the economy gate guessed a model's budget class from its NAME prefix. Both were Claude-
# shaped: the case passed any unknown string through untouched, and the prefix rule read every
# non-Claude id as frontier no matter how cheap it was. Neither could say "I do not know this
# one" — and that sentence is the whole safety property here.
#
# What each block below defends, in one line each:
#   A registry shape   — one reviewed table, no duplicate id, ONE `current` row per family
#   B resolution       — aliases expand, brand words do NOT, hosts do not share a vocabulary
#   C knob validation  — an effort/context a model does not have is refused, not passed on
#   D conservative     — an unreviewed id is `unknown` and `unknown` costs a written rationale
#   E generation       — the wrapper carries the override, carries NO ignored key, is stable
#   F launcher         — the flags really get built, and a duplicated flag stops the run
#   G apply-subagents  — explicit, atomic, keeps unrelated settings, keeps its backup
#   H canon skills     — delegation and output paths stay host-neutral, model choice defers here
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=bin/lib-models.sh
. "$ROOT/bin/lib-models.sh"

FAIL=0
section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }
M="bash $ROOT/bin/models.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# refuses <label> <command...> — the command must exit non-zero AND say something on stderr.
# A silent refusal is only marginally better than a silent substitution.
refuses() {
  local label="$1"; shift
  local e; e="$("$@" 2>&1 >/dev/null)"; local rc=$?
  if [ "$rc" -eq 0 ]; then err "$label: expected a refusal, got success"; return; fi
  [ -n "$e" ] && ok "$label refused: $(printf '%s' "$e" | head -1 | cut -c1-90)" \
               || err "$label refused silently (no reason on stderr)"
}

# --- A) registry shape --------------------------------------------------------------------
section "registry — one reviewed table, well formed, latest-within-family enforced"
rows="$(models_rows)"
[ -n "$rows" ] && ok "registry parses ($(printf '%s\n' "$rows" | wc -l | tr -d ' ') rows)" || err "registry empty/unreadable"
bad="$(printf '%s\n' "$rows" | awk -F'\t' 'NF!=9{print NR": "NF" fields"}')"
[ -z "$bad" ] && ok "every row has all 9 columns" || err "malformed rows: $bad"
dups="$(printf '%s\n' "$rows" | cut -f1 | LC_ALL=C sort | uniq -d)"
[ -z "$dups" ] && ok "no duplicate model id" || err "duplicate ids: $dups"
badcls="$(printf '%s\n' "$rows" | awk -F'\t' '$4!="frontier"&&$4!="mid"&&$4!="cheap"{print $1}')"
[ -z "$badcls" ] && ok "every class is one of frontier|mid|cheap" || err "bad class on: $badcls"
badst="$(printf '%s\n' "$rows" | awk -F'\t' '$8!="current"&&$8!="legacy"{print $1}')"
[ -z "$badst" ] && ok "every status is current|legacy" || err "bad status on: $badst"
# "Newest generation of the tier" as a MECHANISM, not a sentence: a family may hold exactly one
# `current` row, so promoting a new id forces demoting the old one in the same diff.
multi="$(printf '%s\n' "$rows" | awk -F'\t' '{c[$2]+=($8=="current")} END{for(f in c) if(c[f]!=1) print f}')"
[ -z "$multi" ] && ok "exactly one 'current' row per family (latest-within-family is mechanical)" \
                || err "families with more than one current row: $multi"
# Every effort/context token must be one the host CLI actually parses.
badtok=""
while IFS=$'\t' read -r id _f _a _c effs ctxs _h _s _src; do
  [ "$effs" = "none" ] || for e in $(printf '%s' "$effs" | tr ',' ' '); do
    case " $(models_host_efforts) " in *" $e "*) ;; *) badtok="$badtok $id:$e" ;; esac
  done
  for c in $(printf '%s' "$ctxs" | tr ',' ' '); do
    case " $(models_host_contexts) " in *" $c "*) ;; *) badtok="$badtok $id:$c" ;; esac
  done
done <<< "$rows"
[ -z "$badtok" ] && ok "every effort/context token is a level the Copilot CLI parses" || err "unparsable tokens:$badtok"

# --- B) resolution ------------------------------------------------------------------------
section "resolution — aliases expand, brand words do not, hosts keep separate vocabularies"
[ "$($M resolve opus)" = "claude-opus-5" ]    && ok "opus -> claude-opus-5 (copilot)"    || err "opus resolved wrong"
[ "$($M resolve sonnet)" = "claude-sonnet-5" ] && ok "sonnet -> claude-sonnet-5 (copilot)" || err "sonnet resolved wrong"
[ "$($M resolve haiku)" = "claude-haiku-4.5" ] && ok "haiku -> claude-haiku-4.5 (copilot)" || err "haiku resolved wrong"
[ "$($M resolve gpt-6-astra)" = "gpt-6-astra" ] && ok "a reviewed concrete id resolves to itself" || err "gpt-6-astra did not resolve"
# Claude Code takes the TIER alias, not a Copilot id — the two hosts do not share a namespace.
[ "$($M resolve opus --host claude)" = "opus" ] && ok "opus --host claude stays the tier alias (Claude Code back-compat)" || err "claude host resolution changed"
refuses "a Copilot id on the claude host"   $M resolve gpt-6-astra --host claude
refuses "a Copilot id on the claude host"   $M resolve claude-opus-5 --host claude
refuses "the codex host (no model pin)"     $M resolve opus --host codex
# THE BRAND-WORD CASE. "Astra" is a product name, not an identifier. A resolver that accepts it
# is a resolver that will accept "the new GPT" next — and pass it straight to --model.
refuses "the bare brand word 'Astra'"       $M resolve Astra
refuses "'gpt-6-astra' capitalised"         $M resolve GPT-6-ASTRA
refuses "an invented id"                    $M resolve gpt-7-nova
refuses "an empty token"                    $M resolve ""
refuses "an unknown host"                   $M resolve opus --host gemini-cli

# --- C) knob validation -------------------------------------------------------------------
section "knobs — an effort/context the model does not have is refused, never forwarded"
$M validate --model gpt-6-astra --effort xhigh --context long_context >/dev/null \
  && ok "astra accepts xhigh + long_context" || err "astra validation failed unexpectedly"
$M validate --model claude-opus-5 --effort max --context long_context >/dev/null \
  && ok "opus-5 accepts max + long_context" || err "opus-5 validation failed unexpectedly"
refuses "effort on a model with no reasoning knob (haiku)" $M validate --model claude-haiku-4.5 --effort high
refuses "long_context on a default-only model"            $M validate --model gpt-5.4-mini --context long_context
refuses "an effort above what the model offers"           $M validate --model gemini-3.8-flash --effort max
refuses "an effort level the CLI does not parse"          $M validate --model gpt-6-astra --effort extreme
refuses "a context tier the CLI does not parse"           $M validate --model gpt-6-astra --context huge
# `none` and `minimal` are host levels but no reviewed model declares them: the registry, not
# the flag parser, has the last word. This is the difference between "the CLI accepts it" and
# "this model has it", and conflating the two is how a knob silently does nothing.
refuses "a host level no reviewed model declares"         $M validate --model gpt-6-astra --effort minimal

# --- D) conservative on unknown ------------------------------------------------------------
section "unknown is not cheap — an unreviewed id classes as unknown and costs a rationale"
[ "$($M class gpt-7-nova)" = "unknown" ] && ok "an unreviewed id classes as 'unknown'" || err "unknown id did not class as unknown"
[ "$($M class opus)" = "frontier" ] && [ "$($M class sonnet)" = "mid" ] && [ "$($M class haiku)" = "cheap" ] \
  && ok "aliases class frontier/mid/cheap" || err "alias classing wrong"
# The economy gate must treat unknown like frontier. Proven by RUNNING it against a fake canon
# whose one agent is an executor pinned to an unreviewed id with no rationale: it must go RED.
FAKE="$TMP/fakecanon"; mkdir -p "$FAKE/agents"
cp -R "$ROOT/bin" "$FAKE/bin"; cp -R "$ROOT/skills" "$FAKE/skills"; mkdir -p "$FAKE/test"
cp "$ROOT/test/test-model-economy.sh" "$FAKE/test/"
cat > "$FAKE/agents/ghost.md" <<'EOF'
---
name: ghost
description: "fixture"
model: "some-unreviewed-model-9"
effort: "medium"
role_class: "executor"
tools: Read
constraints: []
version: "1.0"
maturity: stable
---
EOF
out="$(cd "$FAKE" && bash test/test-model-economy.sh 2>&1)"
printf '%s' "$out" | grep -q "FAIL: ghost.md" \
  && ok "economy gate goes RED on an executor pinned to an unreviewed id with no rationale" \
  || err "economy gate stayed green on an unknown-model executor — unknown was treated as safe"
# ...and the SAME fixture with a written reason passes: the escape hatch still exists.
sed -i.bak 's/^role_class: "executor"/role_class: "executor"\nmodel_rationale: "written reason"/' "$FAKE/agents/ghost.md"
out2="$(cd "$FAKE" && bash test/test-model-economy.sh 2>&1)"
printf '%s' "$out2" | grep -q "FAIL: ghost.md" \
  && err "the written-reason escape no longer works — the gate became unopenable" \
  || ok "a written model_rationale still opens the gate (escape hatch intact)"

# --- E) generation ------------------------------------------------------------------------
section "generation — override reaches the wrapper, no ignored key is emitted, output is stable"
E1="$TMP/e1"; E2="$TMP/e2"
RDA_SYNC_OUT="$E1" bash bin/sync.sh --emit-only >/dev/null 2>&1
RDA_SYNC_OUT="$E2" bash bin/sync.sh --emit-only >/dev/null 2>&1
BA="$E1/copilot/agents/baccio.md"
grep -qE '^model: gpt-6-astra$' "$BA" && ok "the Copilot-only override reaches the generated wrapper" || err "copilot_model override missing from $BA"
grep -qE '^model:[[:space:]]*"opus"' agents/baccio.md && ok "the canon tier for Claude Code is untouched by that override" || err "the override leaked into the canon model: field"
# Copilot's agent schema has NO effort/context field and ignores unknown keys in silence (the
# `metadata:` scar). A key that looks like configuration and behaves like a comment is worse
# than no key: it stops anyone from looking for the setting that actually works.
badkey="$(grep -lE '^(effort|effortLevel|context|contextTier|reasoning[-_]effort):' "$E1"/copilot/agents/*.md 2>/dev/null)"
[ -z "$badkey" ] && ok "no generated agent carries an effort/context key Copilot would ignore" || err "ignored key emitted in: $badkey"
# Every emitted model pin must still be a reviewed id — a stale wrapper is a silent downgrade.
badpin=""
for f in "$E1"/copilot/agents/*.md; do
  p="$(grep -m1 '^model: ' "$f" | sed 's/^model: //')"
  [ -z "$p" ] && continue
  models_resolve "$p" copilot >/dev/null 2>&1 || badpin="$badpin $(basename "$f"):$p"
done
[ -z "$badpin" ] && ok "every generated model pin is a reviewed registry id" || err "unreviewed pins:$badpin"
diff "$E1/copilot/subagents.json" "$E2/copilot/subagents.json" >/dev/null 2>&1 \
  && ok "subagents.json is deterministic across two runs" || err "subagents.json is non-deterministic"
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); a=d["subagents"]["agents"];
assert a["baccio"]=={"model":"gpt-6-astra","modelPolicy":"required","effortLevel":"high","contextTier":"default"}, a["baccio"]
assert a["wanda"]["effortLevel"]=="medium", a["wanda"]
assert a["explore"]["model"]=="claude-sonnet-5", a["explore"]
assert all(a[n]["modelPolicy"]=="required" for n in ("explore","task","general-purpose","research","code-review","security-review"))' "$E1/copilot/subagents.json" 2>/dev/null \
    && ok "subagents.json is valid JSON and carries model+effortLevel+contextTier per agent" \
    || err "subagents.json malformed or missing the expected knobs"
fi
# Generated Copilot prompts must point at an ABSOLUTE canon path: a prompt runs from the
# session's cwd, and a relative one silently points at nothing there.
badp="$(grep -L "$ROOT/skills/" "$E1"/copilot/prompts/*.prompt.md 2>/dev/null)"
[ -z "$badp" ] && ok "every generated prompt names the canon file by absolute path" || err "relative canon path in: $badp"

# --- F) launcher --------------------------------------------------------------------------
section "launcher — the flags are really built, and a duplicated flag stops the run"
args="$(RDA_DRY_RUN=1 bash bin/copilot-agent.sh baccio -p hello 2>&1)"
printf '%s\n' "$args" | tr '\n' ' ' | grep -q -- "copilot --agent baccio --model gpt-6-astra --effort high --context default -p hello" \
  && ok "baccio launches as: copilot --agent baccio --model gpt-6-astra --effort high --context default -p hello" \
  || err "unexpected argv: $(printf '%s' "$args" | tr '\n' ' ')"
# The prompt survives as ONE argv token: the flags are built as an array, and a flat string
# would have re-split it on the space.
sp="$(RDA_DRY_RUN=1 bash bin/copilot-agent.sh baccio -p 'hello world' 2>&1)"
printf '%s\n' "$sp" | grep -qx 'hello world' && ok "a spaced prompt stays a single argv token" || err "argv re-split on whitespace"
# --context is omitted for a model with a SINGLE tier: a flag that cannot mean anything is
# noise, and noise gets copy-pasted onto a model where it does mean something.
FX="$TMP/fx-agent"; mkdir -p "$FX/agents"
printf -- '---\nname: fx\ncopilot_model: "gpt-5.3-codex"\nmodel: "sonnet"\neffort: "high"\nproviders: [copilot]\n---\n' > "$FX/agents/fx.md"
fxa="$(models_agent_args "$FX/agents/fx.md" | tr '\n' ' ')"
printf '%s' "$fxa" | grep -q -- '--context' && err "--context emitted for a single-tier model: $fxa" || ok "--context omitted when the model has one tier ($fxa)"
# ...and no --effort at all for a model with no reasoning knob.
printf -- '---\nname: fx2\ncopilot_model: "claude-haiku-4.5"\nmodel: "haiku"\nproviders: [copilot]\n---\n' > "$FX/agents/fx2.md"
fx2="$(models_agent_args "$FX/agents/fx2.md" | tr '\n' ' ')"
printf '%s' "$fx2" | grep -q -- '--effort' && err "--effort emitted for a model with no reasoning knob: $fx2" || ok "--effort omitted for a model with no reasoning knob ($fx2)"
targs="$(RDA_DRY_RUN=1 bash bin/copilot-agent.sh thor 2>&1 | tr '\n' ' ')"
printf '%s' "$targs" | grep -q -- "--model claude-sonnet-5 --effort high" && ok "thor keeps the canon sonnet tier (executor default preserved)" || err "thor argv wrong: $targs"
# A second --model would silently win over ours: the session would not be running what the
# launcher just printed. Refuse instead.
refuses "a caller-supplied --model next to the pinned one" bash bin/copilot-agent.sh baccio --model gpt-5.5
refuses "a caller-supplied --effort"                        bash bin/copilot-agent.sh baccio --effort max
refuses "a caller-supplied --context=long_context"          bash bin/copilot-agent.sh baccio --context=long_context
refuses "an agent that is not in the canon"                 bash bin/copilot-agent.sh nosuchagent
# No permission widening: a launcher that quietly adds --allow-all is a bigger change than the
# one it advertises.
printf '%s' "$targs$args" | grep -qE '\-\-allow-all|--yolo|--allow-all-tools' \
  && err "the launcher injects permission flags" || ok "the launcher adds no permission flags"

# --- G) apply-subagents -------------------------------------------------------------------
section "apply-subagents — explicit, atomic, preserves unrelated settings, keeps its backup"
CFG="$TMP/settings.json"
printf '{\n  "theme": "high-contrast",\n  "model": "claude-opus-5",\n  "subagents": { "agents": { "mine": { "model": "gpt-5.5" } } }\n}\n' > "$CFG"
before="$(cat "$CFG")"
refuses "apply-subagents without --yes" $M apply-subagents --config "$CFG"
[ "$(cat "$CFG")" = "$before" ] && ok "the refused run wrote nothing" || err "a refused apply still modified the config"
if command -v python3 >/dev/null 2>&1; then
  $M apply-subagents --yes --config "$CFG" >/dev/null 2>&1 && ok "explicit --yes applies" || err "apply-subagents --yes failed"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1]));
assert d["theme"]=="high-contrast", "theme lost"
assert d["model"]=="claude-opus-5", "session model lost"
assert d["subagents"]["agents"]["mine"]["model"]=="gpt-5.5", "foreign subagent lost"
assert d["subagents"]["agents"]["baccio"]["model"]=="gpt-6-astra", "our subagent missing"' "$CFG" 2>/dev/null \
    && ok "unrelated keys and a foreign subagent survive the merge" || err "the merge dropped unrelated settings"
  [ -n "$(find "$TMP" -name 'settings.json.bak-rdos-*' 2>/dev/null)" ] && ok "a timestamped backup is kept (never deleted)" || err "no backup written"
  # Idempotent: applying twice must not multiply anything.
  $M apply-subagents --yes --config "$CFG" >/dev/null 2>&1
  n="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["subagents"]["agents"]))' "$CFG")"
  [ "$n" -ge 2 ] && ok "second apply is idempotent ($n subagents, no duplication)" || err "subagent map corrupted on re-apply"
  [ "$(find "$TMP" -name 'settings.json.bak-rdos-*' | wc -l | tr -d ' ')" -eq 2 ] \
    && ok "rapid re-apply never overwrites the previous backup" || err "backup was overwritten"
fi
# sync.sh must NEVER apply the fragment — emitting it and writing Copilot's own settings are
# two different acts, and only the second one is destructive. Comments naming the command are
# fine; an executable line calling it is not.
grep -vE '^[[:space:]]*#' bin/sync.sh | grep -q 'apply-subagents' \
  && err "sync.sh CALLS apply-subagents — the install path would write Copilot's settings" \
  || ok "sync.sh never applies the fragment (emission and application stay separate)"

section "H canon skills — no host-specific delegation or output path"
# A skill that says "use the Agent tool" or writes to ~/.claude/reports/ is a Claude-only
# instruction wearing a cross-host `providers:` header. Both were true until 2026-09-05.
# The model-selection-policy skill is exempt: naming each host's tool is its job.
# shellcheck disable=SC2088  # the tilde is the literal string being searched for, not a path
h="$(grep -rln '~/\.claude/reports/' skills/ 2>/dev/null || true)"
[ -z "$h" ] && ok "no canon skill hardcodes one CLI's home for its reports" \
  || err "Claude-only report path still in: $h"
h="$(grep -rlnE '\((Agent|Task) tool[,)]' skills/ agents/ 2>/dev/null \
     | grep -v 'skills/model-selection-policy/' || true)"
[ -z "$h" ] && ok "delegation is described host-neutrally (no bare '(Agent tool)')" \
  || err "host-specific delegation tool named as the only mechanism in: $h"
# Every delegating skill must route model choice through the one policy, not restate it.
for s in premortem focus-group problem-validation long-running-jobs; do
  grep -q 'model-selection-policy' "skills/$s/skill.md" \
    && ok "$s defers model/effort/context to the single policy" \
    || err "$s delegates without pointing at model-selection-policy"
done
# The installed third-party copy is upstream's; the policy must say so out loud.
grep -q 'gstack' skills/model-selection-policy/skill.md \
  && ok "the policy states the gstack carve-out (upstream, never hand-edit the installed copy)" \
  || err "no upstream carve-out documented for third-party installed skills"

section "I strict delegation and input failures"
refuses "legacy model selection" $M resolve gpt-5-mini
refuses "placeholder alias" $M resolve -
refuses "task-only model on CLI" $M resolve grok-4.6
[ "$($M resolve grok-4.6 --host copilot-task)" = grok-4.6 ] \
  && ok "task-only model resolves only on its listed surface" || err "task surface resolution failed"
refuses "missing flag value" $M validate --effort
refuses "missing resolve host" $M resolve opus --host
refuses "agent path traversal" bash bin/copilot-agent.sh ../agents/baccio
refuses "conflicting agent flag" bash bin/copilot-agent.sh baccio --agent thor
RDA_DRY_RUN=1 bash bin/copilot-agent.sh baccio -p --model >/dev/null \
  && ok "a prompt that resembles a flag stays prompt data" || err "prompt was parsed as a flag"
printf '{"subagents":null}\n' > "$TMP/invalid.json"
refuses "invalid existing settings schema" $M apply-subagents --yes --config "$TMP/invalid.json"
[ "$(cat "$TMP/invalid.json")" = '{"subagents":null}' ] \
  && ok "invalid settings are not overwritten" || err "invalid settings changed"
printf -- '---\nmodel: "gpt-5.4-mini"\ncopilot_context: "long_context"\n---\n' > "$FX/badctx.md"
refuses "unsupported declared context on single-tier model" models_agent_args "$FX/badctx.md"

printf '\n'
[ "$FAIL" -eq 0 ] && { echo "test-model-registry: PASS"; exit 0; }
echo "test-model-registry: FAIL"; exit 1
