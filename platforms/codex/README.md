# Codex → roberdan-os

Codex reads `AGENTS.md` natively from the repo root. No wrapper needed: point Codex
at the roberdan-os root (or symlink `AGENTS.md` into the target repo).

Config snippet (if an explicit instructions file is needed):
    codex --instructions "$RDA_OS/AGENTS.md"
