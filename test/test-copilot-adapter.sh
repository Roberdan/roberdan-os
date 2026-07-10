#!/usr/bin/env bash
# test/test-copilot-adapter.sh — proves the native GitHub Copilot adapter:
#   A. deterministic emission of copilot agents + extension (mapped frontmatter, baked ROOT)
#   B. collision-safe install into ~/.copilot/agents + ~/.copilot/extensions/roberdan-os
#      (fresh symlink, never overwrite, idempotent) and NO writes when ~/.copilot is absent
#   C. the extension loads (real ESM import via a stubbed @github/copilot-sdk) and registers
#      the expected namespaced tools + lifecycle hooks
#   D. the PreToolUse guard mapping is correct end-to-end: deny/ask on dangerous actions,
#      allow (undefined) on safe ones, and FAIL-SAFE (ask) when a guard errors — never a
#      silent success-shaped allow
#   E. idle Stop-chain dedup/throttle wiring is present
#   F. privacy: the extension never reads/echoes mcp-config.json contents (secrets)
# Fully isolated (temp HOME/targets) — never touches the real ~/.copilot or ~/.claude.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

command -v node >/dev/null 2>&1 || { echo "test-copilot-adapter: SKIP (node not installed)"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- A) deterministic emission ------------------------------------------------
section "emission — copilot agents + extension are generated, mapped, deterministic"
E1="$TMP/emit1"; E2="$TMP/emit2"
RDA_SYNC_OUT="$E1" bash bin/sync.sh --emit-only >/dev/null 2>&1
RDA_SYNC_OUT="$E2" bash bin/sync.sh --emit-only >/dev/null 2>&1
AGENTS="$E1/copilot/agents"; EXT="$E1/copilot/extension/roberdan-os/extension.mjs"

# one wrapper per canon agent that lists provider `copilot`
canon_copilot_agents=0
for a in agents/*.md; do
  awk '/^---$/{c++;next} c==1' "$a" | grep -qiE '^providers:.*copilot' && canon_copilot_agents=$((canon_copilot_agents+1))
done
emitted_agents=$(find "$AGENTS" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$emitted_agents" -eq "$canon_copilot_agents" ] && [ "$emitted_agents" -gt 0 ] \
  && ok "one copilot agent per copilot-provider canon agent ($emitted_agents)" \
  || err "agent count mismatch: emitted=$emitted_agents canon=$canon_copilot_agents"

# frontmatter: description REQUIRED + quoted, tools mapped to aliases, model mapped
if [ -f "$AGENTS/thor.md" ]; then
  grep -qE '^description: "' "$AGENTS/thor.md" && ok "thor description is a required quoted scalar" || err "thor description missing/unquoted"
  grep -qE '^tools: \[read, search, execute\]$' "$AGENTS/thor.md" && ok "thor tools mapped (Read,Grep,Glob,Bash -> read,search,execute deduped)" || err "thor tools mapping wrong: $(grep -m1 '^tools:' "$AGENTS/thor.md")"
  grep -qE '^model: claude-sonnet' "$AGENTS/thor.md" && ok "thor model mapped (sonnet -> claude-sonnet-*)" || err "thor model mapping wrong: $(grep -m1 '^model:' "$AGENTS/thor.md")"
else
  err "expected $AGENTS/thor.md to be generated"
fi
if [ -f "$AGENTS/baccio.md" ]; then
  grep -qE '^tools: \[read, edit, execute, search, web\]$' "$AGENTS/baccio.md" && ok "baccio tools mapped (incl. Write->edit, WebSearch/WebFetch->web)" || err "baccio tools mapping wrong: $(grep -m1 '^tools:' "$AGENTS/baccio.md")"
  grep -qE '^model: claude-opus' "$AGENTS/baccio.md" && ok "baccio model mapped (opus -> claude-opus-*)" || err "baccio model mapping wrong"
fi

# extension generated, baked ROOT, valid syntax, deterministic
if [ -f "$EXT" ]; then
  ok "extension.mjs generated"
  node --check "$EXT" 2>/dev/null && ok "extension.mjs is valid ES module syntax" || err "extension.mjs failed node --check"
  grep -qF "process.env.RDA_OS || \"$ROOT\"" "$EXT" && ok "extension bakes the repo ROOT (env RDA_OS still overrides)" || err "extension ROOT not baked/expanded"
  grep -qE '__RDA_OS_DEFAULT__' "$EXT" && err "unexpanded __RDA_OS_DEFAULT__ placeholder left in extension" || ok "no unexpanded placeholder remains"
else
  err "expected extension.mjs to be generated at $EXT"
fi

if diff -r "$E1/copilot/agents" "$E2/copilot/agents" >/dev/null 2>&1 \
   && diff "$EXT" "$E2/copilot/extension/roberdan-os/extension.mjs" >/dev/null 2>&1; then
  ok "emission is deterministic (agents + extension byte-identical across two runs)"
else
  err "emission is non-deterministic"
fi

# --- F) privacy: extension never reads/echoes mcp-config contents -------------
section "privacy — extension only tests for the gbrain token, never reads/prints mcp-config contents"
if grep -qE 'readFileSync\(mcp\b' "$EXT"; then
  # A read is only acceptable if the bytes feed a boolean gbrain presence test and are never
  # returned or logged (mcp-config.json is Copilot-owned and holds secrets).
  if grep -qE '/"gbrain"/\.test\(readFileSync\(mcp' "$EXT" \
     && ! grep -qE '(return|session\.log)[^;]*readFileSync\(mcp' "$EXT"; then
    ok "mcp-config opened only for a boolean gbrain presence test (contents never surfaced)"
  else
    err "extension may surface mcp-config.json contents (secret-bearing, Copilot-owned)"
  fi
elif grep -qE 'readFileSync\([^)]*mcp' "$EXT"; then
  err "extension reads mcp-config in an unaudited way — verify contents are never surfaced"
else
  ok "extension does not read mcp-config.json at all"
fi

# --- B) install: collision-safe + no-write-when-absent ------------------------
section "install — collision-safe symlinks; no writes when ~/.copilot is absent"
# absent: parent of the skills dir never created -> nothing must be written
ABSENT="$TMP/absent"; mkdir -p "$ABSENT"
aout="$(RDA_CLAUDE_SKILLS_DIR="$TMP/cl-abs" RDA_COPILOT_SKILLS_DIR="$ABSENT/.copilot/skills" \
    RDA_POINTER_HOME="$TMP/ptr-abs" RDA_FORCE_CODEX=0 RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install 2>&1)"
[ -e "$ABSENT/.copilot" ] && err "install created ~/.copilot when it was absent" || ok "no ~/.copilot created when absent"
printf '%s\n' "$aout" | grep -q "^SKIP copilot agents:" && ok "agents install SKIP printed when Copilot absent" || err "expected SKIP for absent copilot agents"
printf '%s\n' "$aout" | grep -q "^SKIP copilot extension:" && ok "extension install SKIP printed when Copilot absent" || err "expected SKIP for absent copilot extension"

# present: fresh install + collision + idempotency
CO="$TMP/home/.copilot"; mkdir -p "$CO"
# pre-existing collision: an agent file already at thor.md (another system) must be untouched
mkdir -p "$CO/agents"; printf 'FOREIGN (do not touch)\n' > "$CO/agents/thor.md"
pout="$(RDA_CLAUDE_SKILLS_DIR="$TMP/cl-pres" RDA_COPILOT_SKILLS_DIR="$CO/skills" \
    RDA_POINTER_HOME="$TMP/ptr-pres" RDA_FORCE_CODEX=0 RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install 2>&1)"
[ -L "$CO/agents/baccio.md" ] && ok "fresh agent (baccio) installed as symlink" || err "baccio agent not symlinked"
[ "$(cat "$CO/agents/thor.md")" = "FOREIGN (do not touch)" ] && ok "colliding agent (thor.md) left untouched" || err "colliding agent was overwritten"
[ -L "$CO/agents/thor.md" ] && err "foreign thor.md was replaced with a symlink" || ok "foreign thor.md still a plain file"
printf '%s\n' "$pout" | grep -q "^SKIP agent thor:" && ok "SKIP printed for colliding agent" || err "expected SKIP for colliding agent thor"
[ -L "$CO/extensions/roberdan-os/extension.mjs" ] && ok "extension installed as symlink" || err "extension not symlinked"
node --check "$CO/extensions/roberdan-os/extension.mjs" 2>/dev/null && ok "installed extension resolves + valid syntax" || err "installed extension invalid"

# idempotent: second run installs nothing new
pout2="$(RDA_CLAUDE_SKILLS_DIR="$TMP/cl-pres" RDA_COPILOT_SKILLS_DIR="$CO/skills" \
    RDA_POINTER_HOME="$TMP/ptr-pres" RDA_FORCE_CODEX=0 RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install 2>&1)"
[ "$(printf '%s\n' "$pout2" | grep -c '^INSTALL agent ')" -eq 0 ] && ok "second run installs 0 new agents (idempotent)" || err "second run re-installed agents"
printf '%s\n' "$pout2" | grep -q "^SKIP copilot extension: .* già presente" && ok "second run skips the existing extension (never overwrite)" || err "second run did not skip existing extension"

# --- C/D/E) load shape + guard mapping via a stubbed SDK -----------------------
section "extension load — registers namespaced tools + hooks; guard mapping deny/ask/allow/fail-safe"
STAGE="$TMP/stage"; mkdir -p "$STAGE/node_modules/@github/copilot-sdk"
cp "$EXT" "$STAGE/extension.mjs"
cat > "$STAGE/node_modules/@github/copilot-sdk/package.json" <<'JSON'
{ "name": "@github/copilot-sdk", "version": "0.0.0-stub", "exports": { "./extension": "./extension.mjs" } }
JSON
cat > "$STAGE/node_modules/@github/copilot-sdk/extension.mjs" <<'JS'
export async function joinSession(cfg) {
  globalThis.__RDA_CFG = cfg;
  return {
    on(evt, cb) { (globalThis.__H ??= {})[evt] = cb; return () => {}; },
    log: async () => {}, send: async () => {}, sendAndWait: async () => ({}), workspacePath: undefined, rpc: {},
  };
}
JS

# A throwaway git repo checked out on `main` with a real file, so main-guard resolves branch=main.
MREPO="$TMP/mainrepo"; mkdir -p "$MREPO"
( cd "$MREPO" && git init -q -b main && git config user.email t@t && git config user.name t \
  && echo x > code.txt && echo y > notes.md && git add -A && git commit -qm init ) >/dev/null 2>&1

# A fake HOOKS dir whose main-guard EXITS NON-ZERO, to prove the fail-safe (guard error -> ask).
FHOOKS="$TMP/failhooks/hooks"; mkdir -p "$FHOOKS"
printf '#!/usr/bin/env bash\nexit 3\n' > "$FHOOKS/main-guard.sh"; chmod +x "$FHOOKS/main-guard.sh"

cat > "$STAGE/driver.mjs" <<JS
import "./extension.mjs";
const cfg = globalThis.__RDA_CFG;
const out = { ok: [], fail: [] };
const A = (c, m) => (c ? out.ok : out.fail).push(m);

// tool registration + global namespace uniqueness
const names = (cfg.tools || []).map((t) => t.name);
for (const n of ["roberdanos_kanban","roberdanos_pause","roberdanos_resume","roberdanos_verify_done","roberdanos_doctor"])
  A(names.includes(n), "tool " + n + " registered");
A(names.every((n) => n.startsWith("roberdanos_")), "all tool names are roberdanos_-namespaced (globally unique)");

// hook registration
for (const h of ["onSessionStart","onPreToolUse","onPostToolUse","onPostToolUseFailure","onSessionEnd"])
  A(typeof cfg.hooks[h] === "function", "hook " + h + " registered");

const pre = cfg.hooks.onPreToolUse;
// deny: force push
let r = await pre({ toolName: "bash", toolArgs: { command: "git push --force origin main" } });
A(r && r.permissionDecision === "deny", "bash force-push -> deny");
// ask: reset --hard
r = await pre({ toolName: "bash", toolArgs: { command: "git reset --hard HEAD~1" } });
A(r && r.permissionDecision === "ask", "bash reset --hard -> ask");
// allow (undefined): innocuous command
r = await pre({ toolName: "bash", toolArgs: { command: "git status" } });
A(r === undefined, "bash git status -> no override (undefined)");
// deny: write a NON-md file on main
r = await pre({ toolName: "edit", toolArgs: { path: "$MREPO/code.txt" } });
A(r && r.permissionDecision === "deny", "edit non-md on main -> deny");
// allow: markdown carve-out on main
r = await pre({ toolName: "edit", toolArgs: { path: "$MREPO/notes.md" } });
A(r === undefined, "edit .md on main -> no override (carve-out)");
// deny: RELATIVE path on main, repo supplied via workingDirectory (regression guard for the
// cwd-forwarding fix — the extension's own cwd here is \$STAGE, not the repo).
r = await pre({ toolName: "edit", toolArgs: { path: "code.txt" }, workingDirectory: "$MREPO" });
A(r && r.permissionDecision === "deny", "edit RELATIVE non-md on main (workingDirectory forwarded) -> deny");

console.log(JSON.stringify(out));
JS

# Run 1: real guards (RDA_OS = repo root) for deny/ask/allow
res="$(cd "$STAGE" && RDA_OS="$ROOT" node driver.mjs 2>/dev/null)"
if [ -z "$res" ]; then
  err "driver produced no output (extension failed to load against stub SDK)"
else
  echo "$res" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      const o=JSON.parse(s);
      for (const m of o.ok) console.log("  ok: "+m);
      for (const m of o.fail) { console.log("  FAIL: "+m); process.exitCode=1; }
    });' || FAIL=1
fi

# Run 2: fail-safe — a guard that errors must map to ASK, never a silent allow
cat > "$STAGE/driver-failsafe.mjs" <<JS
import "./extension.mjs";
const pre = globalThis.__RDA_CFG.hooks.onPreToolUse;
const r = await pre({ toolName: "edit", toolArgs: { path: "/tmp/whatever.txt" } });
console.log(JSON.stringify(r || null));
JS
fres="$(cd "$STAGE" && RDA_OS="$TMP/failhooks" node driver-failsafe.mjs 2>/dev/null)"
if printf '%s' "$fres" | grep -q '"permissionDecision":"ask"'; then
  ok "guard execution failure maps to ASK (fail-safe, never a silent allow)"
else
  err "guard failure did NOT fail-safe to ask — got: $fres"
fi

# E) idle Stop-chain dedup/throttle — BEHAVIORAL: fire the idle handler twice rapidly and prove
# the chain runs only once (throttle + reentrancy guard). A temp RDA_OS whose only hook is a
# marker auto-checkpoint.sh lets us count real chain runs.
section "idle Stop-chain — dedup/throttle (fire twice -> chain runs once) + documented limitation"
grep -q 'session.on("session.idle"' "$EXT" && ok "registers a session.idle listener (Stop analog)" || err "no session.idle listener"
grep -q 'chainRunning' "$EXT" && grep -q 'THROTTLE_MS' "$EXT" && ok "reentrancy guard + throttle present in source" || err "missing dedup/throttle guards"

DEDUP_OS="$TMP/dedup-os"; mkdir -p "$DEDUP_OS/hooks"
COUNTER="$TMP/dedup-counter"; : > "$COUNTER"
printf '#!/usr/bin/env bash\necho x >> "$RDA_TEST_COUNTER"\n' > "$DEDUP_OS/hooks/auto-checkpoint.sh"
chmod +x "$DEDUP_OS/hooks/auto-checkpoint.sh"
cat > "$STAGE/driver-idle.mjs" <<JS
import "./extension.mjs";
const idle = (globalThis.__H || {})["session.idle"];
if (typeof idle !== "function") { console.log("NO_IDLE"); process.exit(0); }
idle(); idle(); idle();                       // three rapid turns
await new Promise((r) => setTimeout(r, 600));  // let the (single) chain finish
console.log("DONE");
JS
( cd "$STAGE" && RDA_OS="$DEDUP_OS" RDA_TEST_COUNTER="$COUNTER" node driver-idle.mjs >/dev/null 2>&1 )
runs=$(wc -l < "$COUNTER" | tr -d ' ')
[ "$runs" = "1" ] && ok "chain ran exactly once for 3 rapid idles (throttle/dedup works)" \
  || err "chain ran $runs times for 3 rapid idles — expected 1 (dedup/throttle broken)"

# --- Result --------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "test-copilot-adapter: PASS"; exit 0; else echo "test-copilot-adapter: FAIL"; exit 1; fi
