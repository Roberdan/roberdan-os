# Choosing the world: Apple or TED

Most demo films fail before a frame is shot, because nobody decided **what kind of film it
is**. The result is a hybrid: too much narration to be a product film, too many feature cards
to be a talk. It looks like a slideshow with ambition.

**Gate: the owner picks a world before the script is written.** Offer exactly these two, in
one sentence each, and say which you recommend and why. Never blend them. If both are wanted,
make two films from one set of footage — never one film that hedges.

Sourced from the reference-analysis doctrine in `apple-designer` (transfer principles, never
identity) and from TED's own guidance — Chris Anderson, *TED Talks: The Official TED Guide to
Public Speaking*, and the TED Commandments.

## The two worlds at a glance

| | **Apple world** | **TED world** |
|---|---|---|
| Who speaks | A narrator you never see | A person you see, in first person |
| What the viewer buys | The product | The idea |
| Opening | The thing itself, fast | A story or a question |
| Authority comes from | Craft and restraint | Honesty and standing |
| Structure | Demonstration | Throughline |
| Music | Designed, continuous | Sparse or absent |
| Text on screen | Minimal, never a bullet | Almost none |
| Failure mode | Beautiful and empty | Sincere and shapeless |
| Needs | High-grade footage | A real person with a real stake |

## Apple world — the rules that actually matter

The instruction "make it like Apple" is a trap as much as a gift: it is usually heard as
*expensive-looking*, when the real principle is **selectivity**. More money on screen is not
the reference; fewer things on screen is.

1. **The product arrives within the first six to eight seconds.** Not the logo, not the
   metaphor, not the mission — the thing working. Everything the viewer is asked to feel later
   is earned by having seen it first.
2. **Demonstrate, never enumerate.** A capability that cannot be shown working is cut, not
   described. Full-screen claim cards are the tell of a film that could not shoot its own product.
3. **One idea per shot, and the shot holds.** Confidence reads as willingness to stay.
4. **Real light, real hands, real interface.** Fabricated product footage is disqualifying.
5. **The score is designed, not selected.** It sits under the voice and never swells to
   manufacture an emotion the picture has not produced.
6. **Silence is a tool.** The most expensive second in most product films is the quiet one.
7. **End on the product and one action.** Not the mark alone.

**The honest caveat:** this world is unforgiving when footage is thin, because it has nothing
to hide behind. Choose it only when the product genuinely photographs well and you can shoot
a real interaction. Otherwise TED world will produce a better film from the same material.

## TED world — the rules that actually matter

TED's own first constraint is the one people forget: **you may not sell from the stage.** A
demo film obviously has something to sell, so the adaptation is precise — the film gives the
audience an idea, and the product appears as *evidence that the idea is real*, never as the
subject.

1. **Write the throughline first: one sentence, fifteen words or fewer.** Everything in the
   film hangs off it. If a beat does not serve it, the beat is cut. If you cannot write it,
   you do not yet have a film.
2. **Script the first minute deliberately** — curiosity, surprise, or a story. It buys trust
   and previews the journey. In a two-minute film this is the first fifteen seconds.
3. **Arc, not agenda:** context (why this matters) → a specific story → the insight it yields
   → a conclusion the viewer can carry. Never a feature order.
4. **First person, and a real stake.** The talk only you can give. This world requires
   somebody with standing to speak — a founder, a parent, a user. Without that person it
   collapses into voiceover with extra steps.
5. **Admit what you do not know.** Stated uncertainty is the mechanism that makes the rest
   credible. It is also, conveniently, the truth.
6. **No ego, no schtick, no reading.** Delivery is conversational. A perfectly smooth read is
   worse than a slightly uneven human one.
7. **Visuals serve the sentence.** Minimal, and only where the words alone would fail. No
   logos, no bullets.
8. **Brevity is sacred.** TED enforces 18 minutes to force clarity; apply the same discipline
   proportionally, and treat the runtime as fixed before writing.
9. **Laughter is allowed.** One moment of lightness makes a serious film more credible, not less.

**The honest caveat:** without a face and a genuine stake this world is worse than useless —
it reads as a corporate video pretending to be sincere, which audiences detect instantly.

## Making both from one shoot

When the owner wants both, plan the acquisition once and cut twice. This costs roughly 30%
more than one film, not 100%.

- **Shoot for the Apple cut**: it has the stricter footage requirement (coverage, resolution,
  real interaction). TED-world picture needs are a subset.
- **Additionally capture the speaker**: a single quiet location, one lens, eye-line just off
  camera, ten minutes of material. This is the only TED-specific acquisition, and it cannot be
  synthesised. If the person is unavailable, say so and deliver one film, not a fake second one.
- **Write two scripts, never one script read twice.** The Apple script is third person and
  present tense about the product. The TED script is first person and past tense about a
  problem. Sharing sentences between them produces two mediocre films.
- **Score them differently.** Same picture with the same music in both cuts makes the pair
  look like a variant, not a choice.
- **Gate each one separately.** `scripts/delivery-gate.sh` runs on both; a pass on one says
  nothing about the other.

## Recommending between them

Do not present this as a neutral menu — the owner is paying you for a view. Recommend:

- **Apple world** when the product photographs well, a real interaction can be filmed, and the
  audience already believes the problem is real.
- **TED world** when the problem needs establishing, the speaker has genuine standing, or the
  product is early and honest framing serves it better than polish.
- **TED world** in any competition judged partly on motivation, mission or originality —
  judges remember the idea and the person, and every other entrant will have made the
  product film.
