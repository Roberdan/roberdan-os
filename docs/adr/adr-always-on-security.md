# ADR — roberdan-os Always-on: security of exposing memory (G5)

**Status:** Proposed (2026-07-01) · advisory · **Decide:** Roberto (human gate — spend/architecture/memory exposure)
**Security lens:** luca-mode (zero-trust, OWASP-style) applied to a personal/indie setup
**Relates to:** `docs/always-on-design.md` (Path A/B/C), `kanban/todo/G5-always-on.md`, `kanban/todo/FtS-ingest.md` (local-only cards — card content is never in git, see `kanban/README.md`)

> This document is **material for deciding**, not a decision. G5 remains a human gate.
> No kanban card is moved.

## Risk context

G5 wants to make roberdan-os's memory queryable from the Claude app on iPhone when the
Mac is off, exposing the **gbrain MCP server** on an always-on host with auth (bearer token).

The risk is not theoretical. Memory is not "just the vault": the gbrain brain is **multi-source**
(verified with `gbrain sources list`). A mis-scoped MCP endpoint doesn't expose the vault — it
exposes **the whole brain**:

| Source | Pages | Sensitivity |
|---|---|---|
| `vault` | 291 | Personal notes + (post FtS-ingest) **Fight the Stroke financials/contracts** |
| `edufy27` | 42 | `OneDrive-Microsoft/FY27/MicrosoftScout` → **likely Microsoft-confidential** |
| `mirrorbuddy` / `convergio` / `hve-core` / … | 4363 / 918 / 644 / … | Code + design of own products |
| `default` | 43 | **Raw session transcripts** (contain everything) |

Blast radius of a compromised token/tunnel = **the entire second memory**, not a subset.

### The finding that governs everything: `fightthestroke` is a *workspace*, not a *source*

The `FtS-ingest.md` card ingests ~214 confidential FtS documents **into the `vault` source**
(DoD: *"searchable in the vault"*, acceptance: *"a gbrain **vault** query returns the correct FtS doc"*),
tagged `workspace=fightthestroke`.

`workspace` is **frontmatter/metadata**, not a gbrain source boundary. Security consequences:

1. **The tag is NOT a security boundary.** Semantic search operates on embedded chunks and does
   not reliably respect frontmatter. "Expose `vault` but exclude `workspace=fightthestroke`"
   **is not enforceable** with the tool available.
2. **The boundary gbrain actually has is the _source_.** Scoping happens by `source_id`
   (verified: parameter of the MCP `query` schema).
3. Therefore, if FtS ends up inside `vault`, exposing `vault` = exposing the FtS financials. Full stop.

### The second finding: scope is *controllable by the caller*

From the MCP schema `mcp__gbrain__query`, `source_id`:
> *"Pass `__all__` to span every source for trusted local callers; for remote callers `__all__` spans only your **granted sources**."*

Two direct implications:

- **A "default pin to `vault`" is NOT a boundary.** The iPhone client can pass
  `source_id=mirrorbuddy` or `__all__`. Whoever holds the token chooses the source. Pinning a
  default is ergonomics, not security.
- **The real boundary is the _per-remote granted-sources allowlist_** that gbrain applies to
  remote callers (`__all__` for a remote = only its granted sources). That's the control to use,
  and it's the one that must be configured correctly **before** opening the endpoint.

## Options evaluated (from the design's Paths)

Common assumptions: auth = bearer token in the Claude app; no second factor on the app side;
the token lives on a mobile device (losable/stealable).

### Path A — Tunnel to the Mac (Tailscale *or* Cloudflare Tunnel)

The design treats A as one option, but **Tailscale and Cloudflare Tunnel have opposite
threat models** and must be kept separate:

| Sub-variant | Attack surface | Compromised token/credential | Who else can reach the host |
|---|---|---|---|
| **A1 — Tailscale (WireGuard mesh)** | **No public surface.** The MCP is bound to the tailnet; no public hostname to scan/brute-force. | Bearer token alone = **useless**: also requires a device *inside the tailnet* (Tailscale ACL). Real defense in depth. | Only tailnet devices (yours). Tailscale ACLs restrict further. |
| **A2 — Cloudflare Tunnel (public hostname)** | **Public surface.** Hostname reachable by anyone on the Internet; only auth separates it. Becomes a target exposed 24/7. | Token leak *or* Cloudflare Access policy misconfiguration = **access from anywhere on the planet**, no network constraint. | Anyone on the Internet who clears auth. |

- **A1 (Tailscale):** ✅ best risk/effort ratio. No public exposure, defense in
  depth (network + token), ~€0, ~1h. ⚠️ the Mac must stay on (doesn't solve "Mac off").
- **A2 (Cloudflare):** ⚠️ public exposure for an endpoint that talks to your entire memory.
  For this class of data it's a security downgrade versus A1 with no functional gain that
  justifies it. **Not recommended** unless there's a specific need (e.g. access from a device
  that can't be on the tailnet).

### Path B — Small cloud VM (~€5–10/mo)

- ✅ Solves "Mac off" without hardware.
- ❌ **Confidentiality downgrade, borderline disqualifying for FtS.** The confidential FtS
  documents (financials/contracts) **and their embeddings** would physically leave home and live
  on a third-party box. Embeddings are not "anonymous": they are reconstructible/queryable and
  represent the content. For FtS data (and potentially Microsoft-confidential data in `edufy27`)
  this conflicts with the *local-first / review-before-backup* principle written into the same
  FtS-ingest card.
- ❌ Increases the surface: VM OS, patching, provider access, disk snapshots/backups.
- ⚠️ Still needs a front-tunnel (Tailscale in front of the VM, not Postgres/MCP on a public IP).

### Path C — Mac mini home server

- ✅ **Keeps local-first** (gbrain + bge-m3 on GPU + vault stay at home): best privacy,
  confidential data never leaves the building. Solves "Mac off" (the mini is always on).
- ⚠️ Adds a **home LAN surface**: other devices/IoT on the home network. Still needs to be
  fronted by Tailscale, **never** exposed in the clear on the LAN or port-forwarded on the router.
- ❌ One-time hardware cost (~€500) + another host to patch and physically secure.

## Recommendation

**Combination, phased, with scoping as a non-negotiable pre-condition.**

### MANDATORY mitigations before exposing any endpoint (apply to all Paths)

1. **Isolate FtS in a dedicated gbrain source, NOT inside `vault`.**
   Ingest the FtS documents into a separate source (e.g. `vault-fts`), so the exclusion becomes
   *enforceable at the granularity gbrain actually has* (the source). This is the fix that makes
   the "expose only `vault`, exclude FtS" mitigation actually work. Requires **changing the
   destination of the FtS-ingest card** (dedicated source instead of `workspace` inside `vault`).
2. **Security = per-remote granted-sources allowlist, not a default pin.**
   Configure the remote gbrain in *deny-by-default*: the iPhone device gets access **only** to
   explicitly granted sources (e.g. `vault`), and **never** to `vault-fts`, `edufy27`, `default`
   (raw transcripts), nor the code repos. Explicitly verify that `source_id=__all__` and
   `source_id=<any non-granted source>` from remote **fail** (negative test, not trust in the
   default).
3. **Prefer Tailscale over Cloudflare Tunnel.** No public exposure; the token becomes a
   *de facto* second factor behind the network boundary, not the only control.
4. **Treat the bearer token as a revocable secret.** Per-device dedicated token,
   expiration/rotation, known revocation procedure (lost device = revoke token + remove device
   from the tailnet). Never in git.
5. **Read-only + audit.** The remote endpoint exposes only gbrain read/search tools (no
   `put_page`/`delete_page`/`schema_apply_*` from remote). Log remote queries to be able to
   detect abuse.

### Recommended sequence

- **Phase 1 (now, if mobile access is needed):** **Path A1 (Tailscale)** with mitigations 2–5
  already applied. Zero cost, zero public exposure, ~1h. Covers "Mac on, access from iPhone."
  Accepts the limitation: not yet "Mac off".
- **Phase 2 (for true "Mac off"):** **Path C (Mac mini) + Tailscale**, which keeps local-first
  and stays coherent with the FtS card's privacy principle. Path B **only** if Roberto explicitly
  accepts that FtS/edufy27 data **not** be among the sources granted to the cloud box (then the
  VM hosts only non-confidential sources and the downgrade doesn't apply).
- **Avoid Path A2 (Cloudflare public tunnel)** unless there's a specific requirement not covered
  by Tailscale.

## Explicit dependency with FtS-ingest — ordering

**Secure the exposure BEFORE ingesting the confidential FtS data.** Rationale:

- The two cards are both in `todo` and independent. If **FtS-ingest** runs before G5 is
  securely scoped, the FtS financials/contracts become queryable from the remote endpoint
  **the instant** the endpoint is opened — without anyone having decided to expose them.
- It's a *silent* risk: no error, no signal; the confidential data is simply
  sitting there, searchable from the phone.

**Recommended order:**

1. Decide G5 (this ADR) and implement mitigations 1–2 (dedicated `vault-fts` source +
   deny-by-default granted-sources allowlist).
2. **Only then**, run FtS-ingest — into the isolated `vault-fts` source, excluded from the
   remote grant.
3. Verify with a negative test: from the phone, an FtS query **must** return nothing.

If Roberto prefers to do FtS-ingest first (e.g. he needs FtS search locally, right away):
**acceptable**, on condition that the remote G5 endpoint **stays closed** until the isolated
`vault-fts` source and the allowlist are in place. The invariant rule is: *no remote endpoint
open while an unisolated/unexcluded confidential source exists.*

## What NOT to do (anti-patterns)

- ❌ Relying on the `workspace=fightthestroke` tag as an access boundary (it isn't one).
- ❌ Relying on the "default source pin" as security (the caller can change it).
- ❌ Postgres or the gbrain MCP on a public IP / router port-forward.
- ❌ A single shared, non-revocable token, committed to git or the canon.
- ❌ Opening the endpoint before isolating the confidential sources.

## Consequence

The access boundary of remote memory becomes **explicit and enforceable at source
granularity**, deny-by-default, behind a private network. Personal memory stays queryable
from the phone; confidential data (FtS, edufy27, raw transcripts) stays **outside the remote
perimeter** by construction, not by trust. G5 can proceed once Roberto decides spend and Path;
this ADR sets the security conditions that decision must satisfy.
