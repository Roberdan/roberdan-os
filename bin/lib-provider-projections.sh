#!/usr/bin/env bash
# Provider instruction projections generated from the AGENTS.md safety kernel.

emit_safety_kernel() {
  awk '/<!-- safety-kernel:begin -->/{f=1;next} /<!-- safety-kernel:end -->/{exit} f' \
    "$ROOT/AGENTS.md"
}

emit_global_agents_pointer() {
  cat <<EOF
# AGENTS.md → roberdan-os

Thin pointer. Canonical behavior lives in \`AGENTS.md\` inside \`roberdan-os\`
(\`~/GitHub/roberdan-os/AGENTS.md\`) — read that, do not duplicate it here.

Working in any repo under \`~/GitHub\`, by default:
- **Loop engineering** (autonomy, evidence-first, commit per phase, verified done) — code and business alike.
- **Digital twin** kicks in automatically when the output is communication/decision "as Roberto" (draft-not-send for anything external).
- Agents at the right moment: \`@thor\` (done-gate), \`@rex\` (review), \`@luca\` (security), \`@baccio\` (architecture), \`@socrates\` (first-principles), \`@wanda\` (loop).
- Human gates are never automated (see \`roberdan-os/AGENTS.md#human-gates\`).

$(emit_safety_kernel)

$EXEC_FORMAT_BLURB
Full contract: \`roberdan-os/behavior/roberto-mode.md\` § Communicating with Roberto.
EOF
}

emit_codex() {
  local d="$P/codex"
  mkdir -p "$d"
  {
    cat <<'EOF'
# Codex instructions → roberdan-os

This is the bounded Codex projection. The canonical source remains `AGENTS.md` in
`roberdan-os`; read it for full operating detail after applying the safety kernel below.

EOF
    emit_safety_kernel
    cat <<EOF

$EXEC_FORMAT_BLURB

$TWIN_BLURB

Full canon: \`$ROOT/AGENTS.md\`.
EOF
  } > "$d/AGENTS.md"

  cat > "$d/README.md" <<'EOF'
# Codex → roberdan-os

Codex reads `AGENTS.md` natively. `bin/sync.sh` generates a bounded global projection at
`platforms/codex/AGENTS.md`; `--install` places it at `~/.codex/AGENTS.md`.

Config snippet (if an explicit instructions file is needed):
    codex --instructions "$RDA_OS/platforms/codex/AGENTS.md"
EOF
  sed "s|[\$]RDA_OS|$ROOT|g" "$d/README.md" > "$d/README.md.tmp" \
    && mv "$d/README.md.tmp" "$d/README.md"
}
