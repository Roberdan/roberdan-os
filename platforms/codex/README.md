# Codex → roberdan-os

Codex legge `AGENTS.md` nativamente dalla root del repo. Nessun wrapper necessario:
punta Codex alla root di roberdan-os (o symlinka `AGENTS.md` nel repo target).

Config snippet (se serve un instructions-file esplicito):
    codex --instructions "$RDA_OS/AGENTS.md"
