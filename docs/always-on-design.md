# Always-on roberdan-os (Mac off) + iPhone Claude app — honest design

**Goal:** use roberdan-os when the Mac is off, and reach it from the iPhone Claude app.

**The hard truth:** today the engines are local (gbrain Postgres, vault, Ollama bge-m3 on the Mac).
Mac off = engines off. "Always-on" is not a config flag — it needs the memory/retrieval to live on
a box that never sleeps. This is a real (small) infra project, not a tonight-toggle.

## What already works from anywhere
- **The canon** (`roberdan-os`, private git remote) — a cloud/web Claude session already reads it.
  Behavior, skills, kanban, handoff = portable now.
- **A fresh cloud/web agent** can resume via `handoff/latest.md` + `kanban/` (no Mac needed for that).

## What needs hosting (the memory/recall)
gbrain (Postgres + pgvector) + the vault + an embedder, on an always-on machine, exposed as a
**remote MCP** the iPhone Claude app can call (authenticated).

## Three paths (cheapest → most robust)

| Path | How | Mac-off? | Cost/effort |
|---|---|---|---|
| **A. Tunnel to the Mac** | Keep the Mac (or a spare Mac mini) on; expose the local gbrain MCP over the internet via **Tailscale** or a **Cloudflare tunnel** + auth; register that MCP in the iPhone Claude app | No (Mac must stay on) | ~0€, ~1h setup. Immediate. |
| **B. Small cloud VM** | A ~5–10€/mo VM runs Postgres+pgvector (gbrain) + a git-synced vault + an embedder (bge-m3 on CPU, or a hosted embedder) + remote MCP endpoint | **Yes** | small €/mo, ~half-day setup |
| **C. Mac mini as home server** | A cheap always-on Mac mini at home runs the full local stack (gbrain + Ollama GPU + vault) + Tailscale MCP | **Yes** (Mac mini on) | one-time HW, best privacy+quality |

## Recommendation
- **Now (this week):** Path **A** — Tailscale + expose the local gbrain MCP. You get iPhone access to
  your real memory whenever the Mac is on, at zero cost, in an hour. Best first step.
- **For true Mac-off:** Path **C** (a €500 Mac mini home server) keeps everything **local-first**
  (privacy + bge-m3 GPU) while being always-on — the most on-brand answer. Path **B** if you'd rather
  not own hardware and accept a cloud box (embeddings would leave the home unless you run bge-m3 on the VM).

## Concrete first action (Path A, when you want it)
1. `brew install tailscale` (or Cloudflare `cloudflared`), sign in.
2. Run gbrain's MCP server bound to the tailnet; note the URL + a bearer token.
3. In the iPhone Claude app → add the remote MCP with that URL + token.
4. Test: from the phone, "search my vault for X" → hits local gbrain over the tunnel.

**Honest limit:** none of the paths is a pure software change I can finish unattended tonight — B/C
need a machine + your go on cost; A needs your Tailscale/Apple-ID auth on the devices. The design is
ready; the switch is a decision + ~1h with you in the loop.
