# roberdan-os: a personal, cross-platform agentic operating system with local-first memory and a self-improving meta-loop

**Author:** Roberto D'Angelo (Fight the Stroke Foundation) · developed in a human–agent pair with Claude (Anthropic)
**Date:** 1 July 2026 · **Version:** 1.0 (English) · **Status:** operating system, single-user, single-machine

---

## Abstract

LLM-based coding assistants (Claude Code, GitHub Copilot, OpenAI Codex) are becoming the primary
layer through which knowledge workers interact with their computer. But their *behavioural
configuration* — agents, skills, hooks, personas, memory — tends to sprawl: divergent copies
across dozens of repositories, in incompatible formats, with no single source of truth, no memory
portable across tools, and no mechanism for continuous improvement. We present **roberdan-os**, a
personal agentic operating system addressing three problems: (1) *behavioural fragmentation* — a
single Markdown canon (`AGENTS.md`) from which per-platform wrappers are generated; (2) *siloed
memory* — durable, **local-first** memory living in the user's Obsidian vault, typed and
semantically indexed, consumable by any tool; (3) *absence of self-improvement* — a **meta-loop**
that captures learnings, consolidates them under human gates, and weekly-watches upstream tool
releases, *proposing* (never applying) adaptations. We also describe a *discovery* layer that
shifts the system from "solving problems" to "identifying which problems are worth solving".

We report an empirical case with an instructive failure, both surfaced by an internal audit: the
Italian-language semantic recall was restored from zero to useful — but not, as first believed, by
migrating to a local model; the real cause was a model *misalignment* between query and storage.
The attempt to migrate to a **local** embedding model (`bge-m3` via Ollama) initially failed
because the engine (gbrain) did not recognise the model's native dimensionality; a targeted
two-line patch to its Ollama *recipe* made embedding genuinely **local** — on-device, free, no API
key, GPU-served. The system is, by construction, **self-proposing, never self-applying** over
behaviour. The guiding metaphor is *Remy*, the rat in *Ratatouille* who steers the chef from
inside the hat: an intelligence that suggests, remembers, criticises and proposes from within the
workflow, while the hands — and every irreversible decision — remain human.

---

## 1. Introduction

### 1.1 The problem

An expert user quickly accumulates, across multiple agentic tools, an ecosystem of configurations:
in the case study, ~200 skills and ~300 agents scattered across 13+ repositories, in 3+ formats,
with the same agent existing in 4–6 divergent copies and the global configuration not even
version-controlled. The problem is not **scarcity** but **maintenance surface versus real use**:
dozens of agents maintained, a handful used. Three recurring pathologies:

1. **Behavioural fragmentation.** No single source of truth; "how I work" is duplicated and
   silently diverges across tools.
2. **Siloed memory.** Each tool has its own memory (e.g. Claude Code's `memory/` folder), unreadable
   by the others. Moving from Claude to Copilot to Codex, the assistant "forgets" who you are and
   what you decided.
3. **No continuous improvement.** The system does not learn from interactions, does not reorganise
   itself, and does not adapt as the underlying tools evolve every week.

### 1.2 Contributions

- A **cross-platform behavioural canon** (§4): logic written once in Markdown, wrappers generated
  for Claude/Copilot/Codex/ChatGPT.
- A **local-first durable memory** (§5): the Obsidian vault as typed source of truth + local
  semantic index, with an empirical result on the choice of embedding model.
- A **gated self-improving meta-loop** (§6): capture → distill → curate → watch, with mechanically
  enforced safety invariants.
- A **discovery layer** (§7): premortem, simulated focus-group, and a *problem-validation*
  orchestrator that estimates which problems are worth solving.
- A **design principle** — *self-proposing, never self-applying* — and its justification (§10).

### 1.3 The metaphor: Remy

*Ratatouille* (Pixar, 2007): a rat with culinary talent steers a clumsy cook by pulling his hair
from inside the hat. The rat has the taste; the hands that cook stay human. roberdan-os is designed
this way: an agentic intelligence that **suggests, remembers, criticises and proposes** from within
the workflow, while irreversible decisions and the public voice remain the human's. Not an
autopilot, but a second brain with its hands tied to the right gates.

---

## 2. Background and related work

- **Premortem / prospective hindsight.** Klein (HBR 2007) shows that imagining a failure that has
  *already happened* yields more specific, honest causes than asking "what could go wrong". Kahneman
  called it his single most valuable decision technique. It is the basis of the `premortem` skill
  (§7), here amplified by a multi-agent fan-out.
- **Three-layer memory (Karpathy).** The vault follows the "immutable sources → curated wiki →
  index" pattern. roberdan-os adds a typed *agent-learning* layer.
- **Semantic retrieval and embeddings.** Recall relies on dense embeddings + vector search (HNSW,
  cosine). We document (§5) how the *hosted vs local* choice of embedding model is decisive for
  cost, privacy and multilingual quality — and how a dimensional mismatch can silently break it.
- **Digital twin & agent persona.** A *twin* layer models the user's voice and judgement; it differs
  from purely conversational twins by coupling to human gates and durable memory.
- **Multi-agent systems & reflection.** The meta-loop and the parallel deep-dives (premortem,
  focus-group) use fan-out of independent agents + consolidation — a reflection/ensemble pattern
  applied to personal decisions, not just code.

---

## 3. System architecture

**Core principle:** *centralised knowledge, per-platform execution, unified behaviour.* Logic lives
once in the canon; runtimes consume it through thin wrappers.

```
                    +-------------------------------------------+
                    |   CANON (Markdown, source of truth)       |
                    |   AGENTS.md . behavior/ . agents/ .       |
                    |   rules/ . skills/ . loop/ . memory/      |
                    +---------------------+---------------------+
             bin/sync.sh generates        |      consumed by
        +----------------------------+----+----+--------------------+
        v              v             v         v                    v
   Claude Code      Copilot       Codex     ChatGPT            (others)
        |                                                            
        |  runtime executes in roberto-mode + loop + twin           
        v                                                           
   +----------------------------------------------------------+     
   |  LOCAL-FIRST MEMORY (Obsidian vault + local gbrain)       | <- cross-platform
   +----------------------------------------------------------+     
        ^                                                           
        |  META-LOOP (launchd): capture -> distill -> curate -> evolve  
        +---------------------------------------------------------- self-proposing
```

Three cross-cutting properties: **daemon-optional** (no always-on service required),
**evidence-first** (done = verified artefacts), **human gates** (irreversible actions pass through
the user).

---

## 4. Cross-platform behavioural canon

`AGENTS.md` is the universal standard (read natively by Codex, Copilot, Cursor); `CLAUDE.md` and
`copilot-instructions.md` become thin pointers. Operating behaviour ("how I work") is distilled in
`behavior/roberto-mode.md` (autonomy, evidence-first, commit-per-phase, done-gate); voice and
relational judgement in `behavior/roberto-voice.md`; the cognitive toolkit (first-principles,
Feynman, decision frameworks) in `behavior/thinking-toolkit.md`. Eight specialised agents
(architect, security, review, done-gate, first-principles, red-team, twin, loop-orchestrator)
activate *at the right moment* rather than being invoked by hand. `bin/sync.sh` generates the
per-platform wrappers from this single canon, eliminating divergence.

---

## 5. Local-first durable memory

### 5.1 Why in the vault, not in the tool's silo

Durable memory does **not** live in Claude's per-tool folder (a silo unreadable by Copilot/Codex)
but in the user's **Obsidian vault**: Markdown readable by any agent, already equipped with a
**typed ontology** (`belongs_to`/`has`/`related_to` relations), version-controlled, backed up, and
semantically indexed by a local engine (gbrain, Postgres + pgvector). Agent learnings live in a
separate namespace (`agent-learnings/`, `type: agent-learning`) so as not to pollute human notes
while staying in the same graph and retrievable by the same engine. The per-tool silo degrades to a
*cache*; its contents are migrated into the vault.

### 5.2 The broken recall, the true cause, and a failed attempt (an honest case)

During construction, Italian semantic recall failed silently (query → 0 results) while English
worked. How we were *wrong* about the cause is the instructive part.

**First hypothesis (partly wrong).** The configured provider (`openai:text-embedding-3-large`) had
exhausted its quota, and the stored vectors came from a model weak on Italian; the proposed fix —
a **local multilingual** model (`bge-m3`, 1024-dim, via Ollama) — would be free, rate-limit-free,
private, and strong on Italian. We ran the migration: config, column `ALTER` (1536→1024), HNSW index
rebuild, full re-embed. Italian recall went from **0 to ≥3 results**. It looked like a success.

**What the internal audit revealed.** An empirical-verification agent measured the actual database
state and found **100% of chunks were still labelled `zeroentropyai:zembed-1`**, not `bge-m3`.
Further verification: gbrain **fixes the embedding model at brain initialisation**
(`DEFAULT_EMBEDDING_MODEL = 'zeroentropyai:zembed-1'`); neither the file-plane config nor the
`GBRAIN_EMBEDDING_MODEL` variable change the model at embed-time. bge-m3 had been downloaded but
**never used**. The local model was not active.

**The true cause of the fix.** Recall did not improve because of bge-m3, but because of **model
alignment**: previously, the *query* was embedded with one model (openai) while the *stored vectors*
used another (zembed-1) → incompatible vector spaces → 0 results. The full re-embed made query and
storage the **same** model (zembed-1@1024) → match → results. A coherence bug, not a language
capability.

**Root-cause diagnosis.** The audit pushed a deeper diagnosis: gbrain's Ollama *recipe* listed only
`nomic-embed-text` (768-dim) and relatives, with `default_dims: 768`. The chosen model, `bge-m3`,
was not in the list and its native dimensionality (1024) was unknown to the engine, which fell back
to the global default (1280) and **rejected** the embed on dimensional inconsistency. Not a
fundamental limit: a **missing value in a registry**.

**The fix and the outcome.** Two lines in the recipe (`ollama.ts`: add `bge-m3`, set `default_dims`
to 1024) + recompilation of the engine. Verification: `ollama ps` shows `bge-m3` loaded at 100% on
GPU, and the embed proceeds **with no API key**. A cosine check of a stored vector against a fresh
bge-m3 embedding of the same text returned **1.0000** — confirming the vectors are genuinely bge-m3.
Embedding is now truly **local**:

| Dimension | Before (hosted) | After the fix (local) |
|---|---|---|
| Model | zembed-1 (ZeroEntropy, hosted) | ollama:bge-m3 (on-device, GPU) |
| Privacy | data leaves the machine | stays on-device |
| Cost / API key | metered / required | zero / none |
| Multilingual (IT) | weak | strong (bge-m3) |

**Lessons.** (1) An observed improvement does not prove the hypothesised mechanism — measure, do
not deduce. (2) An adversarial internal audit that *measures* is what exposed the false claim and
led to the true root cause. (3) Sometimes the obstacle to a correct architectural choice is a
*fixable* defect in a dependency, not a constraint: it is worth diagnosing to the end before giving
up.

---

## 6. The self-improving meta-loop

Four components, orchestrated by `launchd` (firing even when the tool is closed), with one
non-negotiable principle: **self-proposing, never self-applying** over behaviour.

| Component | Function | Gate |
|---|---|---|
| **capture** | appends learning signals to a *staging inbox* (no lock, per-platform) | privacy deny-list, as code |
| **distill** | batch: classifies (5-class taxonomy), dedups against the vault, → *quarantine* | never writes directly to the vault |
| **ontology/curate** | *single-writer*: promotes **approved** candidates to typed vault notes; proposes hygiene (dedup, tombstone) | promotion only if `approved: true`; merge/delete human |
| **evolve** | weekly-watches the changelogs of Claude/Copilot/Codex; **proposes drafts** with source citation | never auto-commits to `behavior/ rules/ agents/ AGENTS.md` |

**Why not a self-updating ontology.** A deliberate design choice (validated by an adversarial
first-principles analysis) was to **cut** the idea of an ontology that merges and rewrites itself:
it would sit on a then-broken retrieval, would be a fourth diverging store, and auto-merge is lossy
and irreversible (violating the human gate). 90% of the value comes from **one type**
(`agent-learning`) + **one human-gated hygiene job** that *reuses* the vault's existing ontology.
Structure lives in **curation**, not in the **automation of judgement**.

---

## 7. Discovery layer: which problems are worth solving

The system must not only solve problems but estimate **which are worth solving**. Three composing,
auto-triggering skills:

- **premortem** — given a plan, assumes it has *already failed six months out* and spawns **one
  agent per failure cause, in parallel**, each producing a story, an underlying assumption, and
  early-warning signs; then synthesises the most likely failure, the most dangerous one, the hidden
  assumption, the revised plan, and a checklist. Breaks the LLM's agreeableness bias.
- **focus-group** — simulates real users: a pool of **persona agents** (persistent panels in the
  vault + ad-hoc), a **moderator**, and a **consolidator**, in four modes (focus group, 1:1
  interviews, usability test, micro-survey). The central risk — *sycophancy* of simulated personas —
  is countered by grounding each persona in real frustrations, alternatives, budget and scepticism,
  and by weighting negative signal above positive.
- **problem-validation** — orchestrator: *does the problem exist?* (focus-group) → *is it worth it?*
  (rubric: severity × frequency × reachability × strategic fit × willingness × cost-of-being-wrong)
  → *would the solution hold?* (premortem). Leverages gstack downstream (`spec`, `office-hours`)
  rather than duplicating it. Default **bias-to-kill**: more valuable to say "not worth it" than to
  confirm.

---

## 8. Cognitive layer and agents

Beyond the operating agents, the system models **judgement**: a *digital twin* that writes and
decides in the user's voice (draft-not-send for anything external), a mandatory red-team (`@board`)
on important decisions, a first-principles agent (`@socrates`) to deconstruct problems, and a
done-gate (`@thor`) that is the only one authorised to declare "done" via empirical verification.
These do not replace the user: they **raise their hand** at the right moment and hand the decision
back.

---

## 9. Evaluation

**Methodology.** The system was evaluated by an **adversarial internal audit**: two independent
agents — one for code/ecosystem review, one for empirical verification that *measures* rather than
trusting claims — examined the repository and runtime state. The audit found (and we then fixed)
three real defects, documented below: it is itself part of the result.

**Verified measures (state as of 1 July 2026):**

| Claim | Actual measure | Result |
|---|---|---|
| Italian recall no longer zero | in-corpus IT query → correct migrated note at 0.92 | OK (content-limited for absent topics) |
| Local embedding active | `ollama ps`: `bge-m3` 100% GPU; keyless embed; cosine stored-vs-fresh = 1.0000 | OK, local |
| Memory migrated to vault | 19 tool memories + paper/ADR/plan migrated, indexed, retrievable | OK |
| Meta-loop pipeline | capture→distill→curate tested end-to-end; launchd exit 0 | OK |
| Privacy gate as code | capture/curate block deny-list names, pass normal content | OK (after fix) |
| Green CI | `test/validate.sh` → all green (frontmatter, links, drift, shellcheck, leak) | OK (after fix) |
| Skills active by default | installed in `~/.claude/skills/`; runtime lists them as auto-invocable | OK |

**Defects the audit found and we fixed in the same session:**
1. The "local embedding" claim was false (§5.2) — reworded; DB labels restored to the truth.
2. **CRITICAL — privacy was not "code"**: capture/distill filtered only the literal path string,
   not content; curate had no check. *Fix:* real deny-list matched before every write, with
   blank/comment lines excluded. Tested.
3. **HIGH — the repository did not pass its own CI**: the skills commit had not regenerated the
   `platforms/` wrappers. *Fix:* wrappers generated and committed; `validate.sh` now green.
4. **MEDIUM — doc/impl mismatch**: ADR/evolve cited `validate.sh` for the path-allowlist; the real
   enforcement is in `post-task-sync.sh` (scoped git add). Corrected.

**Honest note on rigour.** This is a systems/experience paper: comprehensive in breadth and honest,
but not quantitatively rigorous — no formal benchmarks, ablations, or measured recall metrics beyond
spot checks. Strong on *what/why and honesty*, light on *how much*.

---

## 10. Limitations

- **Local embedding just achieved, not yet consolidated.** After the patch (§5.2) the embedder is
  local (`bge-m3` on GPU), and the full corpus re-embed completed; the multilingual recall *quality*
  is content-limited (the vault holds mostly Microsoft career profiles, little stroke/disability
  content). The patch lives in a local fork of gbrain and must be re-applied after an engine update.
- **Built ≠ active-by-default (learned mid-session).** A recurring failure mode: mistaking "committed
  to the repo" for "active in the live environment". Skills had to be *installed* to `~/.claude/skills/`
  and capture *enabled* (`RDA_LEARN=1`) for the "by default" promise to hold — done, but only after
  the gap was surfaced.
- **Declared judgement seams.** `distill` writes `class: TODO` (no automatic classification) and
  `evolve` only fingerprint-diffs changelogs: both need an agent-in-the-loop. The design makes the
  gap harmless (curate rejects `TODO`; evolve is draft-only), but judgement is not automated — and
  should not be.
- **Security must be tested, not assumed.** The audit showed the privacy invariant was a *textual
  promise + human gate*, not code, until implemented. Invariants of a self-referential system must be
  **tested**, because documentation can diverge from implementation.
- **Residual sycophancy.** The focus-group mitigates but does not eliminate simulated-persona
  agreeableness; it is a tool for discovering questions and friction, not a substitute for real users.
- **Single-user, single-machine.** Calibrated to one individual and one machine; cross-platform
  portability is designed but verified primarily on Claude Code.
- **Self-modification risk.** A system that proposes changes to itself needs mechanical invariants
  (draft-only, scoped git-add, human gates, deny-list); their robustness is an assumption to be
  monitored continuously, not an acquired fact.

---

## 11. Discussion: principles that generalise

1. **Local-first for personal memory.** Privacy, zero-cost and availability outweigh a hosted
   model's marginal extra quality — especially in multilingual, sensitive contexts.
2. **Self-proposing, never self-applying.** Useful autonomy stops before the irreversible; value
   lies in *proposing with evidence*, not in acting alone over behaviour.
3. **Reuse > reinvention.** The temptation to build new structure (an ontology, an engine) often
   adds maintenance surface with no ROI; extending what exists is almost always better.
4. **Discovery before solving.** The highest value is not solving better, but choosing the right
   problem — which requires the user's voice and stress-testing the failure *before* the build.
5. **Verification over trust; honesty about failure.** The session's most valuable safeguard was an
   internal audit that measured — it caught a false claim and a critical bug. A system that documents
   its own failures (a wiped brain recovered, mislabelled vectors corrected) is more trustworthy than
   one that reports only success.

---

## 12. Future work

- **Consolidate local embedding:** measure post-migration multilingual recall quality, and propose
  the patch upstream to gbrain (register `bge-m3`@1024) so a local fork is unnecessary.
- Verify real portability on Copilot and Codex (not merely designed).
- Automatic capture from session transcripts (today agent-driven).
- Focus-group panels calibrated on real audiences with consent.
- Longitudinal meta-loop metrics (how many promoted learnings survive review).
- Quantitative evaluation: measured recall/precision on a labelled query set; ablations of the
  meta-loop components.

## 13. Conclusion

roberdan-os shows that an individual can be given a coherent *agentic operating system* across
tools, with its own private, persistent memory, and an improvement cycle that never betrays human
control. Not one more assistant, but a second brain with its hands on the right gates — Remy in the
hat, with the right taste and the hands still human. The session that built it also demonstrated the
method: build, then *audit adversarially*, correct honestly, and keep the irreversible under human
judgement.

---

### Reproducibility and artefacts

Code and canon: git repository `roberdan-os` (~16 commits as of 1 July 2026). Memory: Obsidian vault
(local-first) + gbrain (local Postgres/pgvector); embedding **local** `ollama:bge-m3`@1024 (via a
patch to gbrain's Ollama recipe, commit `f7376b11`). Scheduling: `launchd`. Canon, memory,
orchestration **and** embedding are local-first — no cloud service or API key for core operation.
Empirical checks and audit reproducible via `test/validate.sh`, `ollama ps`, and `gbrain` queries.
